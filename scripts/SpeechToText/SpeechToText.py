#!/usr/bin/env python
from abc import ABC, abstractmethod

import os
import argparse

import json
import copy
import math
import numpy as np

from pydub import AudioSegment
from pydub.utils import make_chunks




class SpeechToText:

  def __init__( self, **args):
    self.result = dict()
    self.chunk_size_ms = 10
    self.model_device = "cpu"
    self.volumes = False
    if 'instance' in args:
      args = args['instance'].__dict__
    if 'data' in args:
      self.result = copy.deepcopy(args['data'])
      del self.result['info']
      args = {**args['data'],**args['data']['info']}
    for k in ["chunk_size_ms", "model_device", "name", "audio_file", "dir", "role"]:
      if k in args:
        print(f"{k}: {args[k]}")
        self.__dict__[k] = args[k]
        self.info[k] = copy.deepcopy(args[k])

  def __add__(self, other):
    addend = {self.role: self, other.role: other}
    host = addend["host"]
    guest = addend["guest"]
    print("TODO: implement merging common attributes\n\n\n")
    if not(host.volumes and guest.volumes):
      raise Exception('imposible to merge recognized tracks! Missing volumes values.')
    ret = type(host)(instance = host)
    ret.name = ''
    ret.volumes = True
    print("TODO merge info !!!")
    for k in ret.info:
      # add info from guest if different - use array
      if isinstance(ret.info[k], str):
        if k in guest.info:
          if ret.info[k] != guest.info[k]:
            ret.info[k] = [ret.info[k], guest.info[k]]
    return ret

  def get_result(self):
    return {**self.result, 'info': self.info}

  def get_name(self):
    return self.name

  def set_name(self, name):
    self.name = name

  def get_info(self):
    return self.info

  def import_recognized(self,result):
    self.result = result

  def __compute_rms(self, chunk):
    """Compute the RMS (Root Mean Square) of an audio chunk."""
    samples = np.array(chunk.get_array_of_samples(), dtype='f')
    #return np.sqrt(np.mean(samples**2))
    return np.sqrt(np.mean(samples**2))

  def compute_volume_over_time(self):
    """Compute the volume of the audio file over time."""
    audio = AudioSegment.from_file(self.audio_file)
    chunks = make_chunks(audio, self.chunk_size_ms)
    # Compute volume for each chunk
    volume_over_time = []
    for i, chunk in enumerate(chunks):
        rms = self.__compute_rms(chunk)
        volume_over_time.append(rms)
    return volume_over_time

  def add_volume_to_spans(self, spans_name, volumes, volumes_compare):
    self.volumes = True
    return self.__add_volume_to_spans(self.result, spans_name, volumes, volumes_compare)

  def __add_volume_to_spans(self, result, spans_name, volumes, volumes_compare):
    if isinstance(result, dict):
      if spans_name in result:
        if isinstance(result[spans_name], list):
          for span in result[spans_name]:
            self.__add_volume_to_span(span, volumes, volumes_compare)
        else:
          self.__add_volume_to_span(result[spans_name], volumes, volumes_compare)
      for key in result:
        self.__add_volume_to_spans(result[key], spans_name, volumes, volumes_compare)
    elif isinstance(result, list):
        for item in result:
          self.__add_volume_to_spans(item, spans_name, volumes, volumes_compare)

  def __add_volume_to_span(self, span, volumes, volumes_compare = []):
    if "start" in span and "end" in span:
      start_index = self.time_to_index(span["start"])
      end_index = self.time_to_index(span["end"]) + 1
      span["volume"] = float(np.sqrt(np.mean(np.array(volumes[start_index : end_index])**2)))
      if volumes_compare:
        span["volume_cmp"] = span["volume"] - float(np.sqrt(np.mean(np.array(volumes_compare[start_index : end_index])**2)))


  def get_dump_path(self,interfix = ""):
    return f"{self.dir}/{self.name}.{interfix}.json"

  def get_export_path(self, suffix = ""):
    if suffix:
      suffix = "." + suffix
    return f"{self.dir}/{self.name}.{self.info['tool']}{suffix}"

  def time_to_index(self, time):
    return int(math.floor(time * self.chunk_size_ms))




  def save_to_srt(self, file):
    if "segments" in self.result:
      for i, segment in enumerate(self.result["segments"]):
          start_time = SpeechToText.format_timestamp(segment["start"])
          end_time = SpeechToText.format_timestamp(segment["end"])
          text = segment["text"]
          file.write(f"{i + 1}\n")
          file.write(f"{start_time} --> {end_time}\n")
          if "speaker" in segment:
             file.write(f"[{segment['speaker']}:]")
          file.write(f"{text}\n\n")
    else:
      print("No segment in result")



  def save_to_tsv(self, level, file):
    self.__save_to_tsv(self.result, level, file)

  def __save_to_tsv(self, result, level , file):
    if isinstance(result, dict):
      for key in result:
        if key == level:
          for span in result[level]:
            start_time = span["start"]
            end_time = span["end"]
            text = span["text"]
            speaker = ""
            if "speaker" in span:
              speaker=f"[{span['speaker']}]"
            file.write(f"{start_time}\t{end_time}\t{speaker}{text}\n")
        else:
          self.__save_to_tsv(result[key], level , file)
    elif isinstance(result, list):
      for item in result:
        self.__save_to_tsv(item, level , file)


  @classmethod
  def filter_result(cls, result, field, speaker, cnt):
    if cls.is_laud(field):
      res = copy.deepcopy(field)
      res["id"] = cnt
      res["speaker"] = speaker
      result.append(res)
      cnt += 1
    return cnt

  @classmethod
  def is_laud(cls, field):
    return field["volume_cmp"] >  -field["volume"] / 10

  @classmethod
  def format_timestamp(cls, seconds):
      hours = math.floor(seconds / 3600)
      seconds %= 3600
      minutes = math.floor(seconds / 60)
      seconds %= 60
      milliseconds = round((seconds - math.floor(seconds)) * 1000)
      seconds = math.floor(seconds)
      formatted_time = f"{hours:02d}:{minutes:02d}:{seconds:02d},{milliseconds:03d}"
      return formatted_time
  @classmethod
  def overlaps(cls, span1, span2):
    return max(span1["start"],span2["start"]) <= min(span1["end"], span2["end"])
  @classmethod
  def is_louder(cls, span1, span2):
    if span1["volume"] > span2["volume"]:
      return 0
    return 1

  @abstractmethod
  def recognize_audio(self):
    pass

