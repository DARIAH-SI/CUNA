from .SpeechToText import SpeechToText

import whisper_timestamped as whisper
from whisper.utils import get_writer


class SpeechToTextWhisper(SpeechToText):

  def __init__( self, **args):
    self.info = dict()
    self.info["tool"] = "whisper"
    if 'instance' in args:
      args = args['instance'].__dict__
    if 'data' in args:
      if 'model_params' in args['data']["info"]:
        args["model_params"] = args['data']["info"]["model_params"]
      args["model_size"] = args['data']["info"]["model_size"]
    for k in ["model_size"]:
      if k in args:
        self.__dict__[k] = args[k]
        self.info[k] = args[k]
    super().__init__(**args)
    if "model_params" in args:
      self.setup = self.__get_whisper_setup(args["model_params"])
      self.info["model_params"] = args["model_params"]

  def __add__(self, other):
    ret = super().__add__(other)
    s1 = self.result["segments"]
    s2 = other.result["segments"]
    ret.result["segments"] = list()
    cnt = 0
    i = j = 0
    while  i < len(s1) or j < len(s2):
      if j >= len(s2):
        cnt = super().filter_result(ret.result["segments"], s1[i], self.role, cnt)
        i += 1
      elif i >= len(s1):
        cnt = super().filter_result(ret.result["segments"], s2[j], other.role, cnt)
        j += 1
      ## get aerage louder and increment it if overlaps:
      elif super().overlaps(s1[i],s2[j]):
        is_louder = super().is_louder(s1[i],s2[j])
        if is_louder == 0:
          cnt = super().filter_result(ret.result["segments"], s1[i], self.role, cnt)
          i += 1
        else:
          cnt = super().filter_result(ret.result["segments"], s2[j], other.role, cnt)
          j += 1
      elif s1[i]["start"] <= s2[j]["start"]:
        cnt = super().filter_result(ret.result["segments"], s1[i], self.role, cnt)
        i += 1
      else:
        cnt = super().filter_result(ret.result["segments"], s2[j], other.role, cnt)
        j += 1
    ret.result["language"] = self.result["language"]
    ret.result["text"] = ''.join(map(lambda x: x["text"],ret.result["segments"]))
    return ret

  def __get_whisper_setup(self, arr):
    setup = dict()
    for item in arr:
      if item == "VAD":
        setup["vad"] = "auditok"
      elif item == "DIS":
        setup["detect_disfluencies"] = True
      elif item == "accurate":
        # beam_size=5, best_of=5, temperature=(0.0, 0.2, 0.4, 0.6, 0.8, 1.0)
        setup["beam_size"] = 5
        setup["best_of"] = 5
        setup["temperature"] = (0.0, 0.2, 0.4, 0.6, 0.8, 1.0)
    return setup

  def get_dump_path(self):
    volume_interfix = ""
    if self.volumes:
      volume_interfix = ".vol"
    return super().get_dump_path(f"whisper-{self.model_size}{volume_interfix}")

  def recognize_audio(self):
    model = whisper.load_model(self.model_size, download_root='.cache', device=self.model_device)
    audio = whisper.load_audio(self.audio_file)
    self.result = whisper.transcribe(model, audio, language="uk", **self.setup)
