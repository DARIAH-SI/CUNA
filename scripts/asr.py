#!/usr/bin/env python
import os
import argparse

from SpeechToText.SpeechToTextWhisper import SpeechToTextWhisper
## from SpeechToText.SpeechToTextWav2Vec import SpeechToTextWav2Vec

import json
import copy
##from datetime import timedelta
import math


import numpy as np
from pydub import AudioSegment
from pydub.utils import make_chunks
args_parser = argparse.ArgumentParser()
recognizers = {
    'whisper' : SpeechToTextWhisper,
    #'wav2vec' : SpeechToTextWav2Vec
}

args_parser.add_argument("--dir", type=str, help="Path to directory with audio files.")

args_parser.add_argument("--host", type=str, help="Host audio filename (without extension).")
args_parser.add_argument("--guest", type=str, help="Guest audio filename (without extension).")
args_parser.add_argument("--speaker", type=str, help="'single'-speaker filename (without extension).")

args_parser.add_argument("--recognized_host", type=str, help="Recognized host result.")
args_parser.add_argument("--recognized_guest", type=str, help="Recognized guest result.")
args_parser.add_argument("--recognized_speaker", type=str, help="Recognized 'single'-speaker result.")

args_parser.add_argument("--recognize", choices = ['whisper', 'wav2vec'], help="Speech to text processing tool.")
args_parser.add_argument("--model_params", nargs='*', choices = ['VAD', 'DIS', 'accurate'], help="Process speech recognition with possible string values VAD(voice activity detection) and DIS(marks disfluences and hesitations).")
args_parser.add_argument("--model_size", default="tiny", choices = ['tiny', 'base', 'small', 'medium', 'large'],  help="Whisper model size.")
args_parser.add_argument("--model_device", default="cpu", choices = ['cpu', 'cuda'],  help="Device")

args_parser.add_argument("--merge", type=str, help="Merge host and guest results.")
args_parser.add_argument("--srt", action='store_true', help="Result to srt.")
args_parser.add_argument("--tsv", action='store_true', help="Result to tsv - word and segments alignment.")



def main(args):
  stt = dict()
  roles = ['host', 'guest', 'speaker']
  for role in roles:
    #path_prefix = args.dir+"/"+stt[role].get_name()
    d = vars(args)
    if role in d and d[role] is not None:
      print(args.recognize)
      if args.recognize:
        stt[role] = recognizers[args.recognize](
                          name = d[role],
                          audio_file = f"{args.dir}/{d[role]}.wav",
                          role = role,
                          **d)
        stt[role].recognize_audio()
        with open(stt[role].get_dump_path(), 'w') as file:
          json.dump(stt[role].get_result(), file, indent=4)
      elif f"recognized_{role}" in d:
        print(role+" "+d[f"recognized_{role}"])
        recognized = d[f"recognized_{role}"]
        with open(f"{args.dir}/{recognized}", 'r') as file:
          data = json.load(file)
          recognizer_name = data["info"]["tool"]
          stt[role] = recognizers[recognizer_name](data = data)
          print(f"LOADED: {role}   "+json.dumps(stt[role].get_info()))
          print(len(stt[role].get_result()["segments"]))

  volume_over_time = dict()
  if args.merge and len(stt) == 2:
    for k in stt:
      print(stt[k].get_info())
      volume_over_time[k] = stt[k].compute_volume_over_time()
    for r1,r2 in [list(stt.keys()), list(stt.keys())[::-1]]:
      print(f"Adding volumes to {r1}:   "+stt[r1].get_name())
      print(stt[r1].get_info())
      # print(len(stt[r1].get_result()["segments"]))
      stt[r1].add_volume_to_spans("segments",volume_over_time[r1], volume_over_time[r2])
      stt[r1].add_volume_to_spans("words",volume_over_time[r1], volume_over_time[r2])
      with open(stt[r1].get_dump_path(), 'w') as file:
        json.dump(stt[r1].get_result(), file, indent=4)
    stt['merged'] = stt['host'] + stt['guest']
    stt['merged'].set_name(args.merge)
    with open(stt['merged'].get_dump_path(), 'w') as file:
      json.dump(stt['merged'].get_result(), file, indent=4)

  for role in stt:
    if args.srt:
      with open(stt[role].get_export_path("srt"), 'w') as file:
        stt[role].save_to_srt(file)
    if args.tsv:
      with open(stt[role].get_export_path("words.tsv"), 'w') as file:
        stt[role].save_to_tsv("words",file)
      with open(stt[role].get_export_path("segments.tsv"), 'w') as file:
        stt[role].save_to_tsv("segments",file)

if __name__ == "__main__":
    main(args_parser.parse_args())