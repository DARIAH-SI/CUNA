PWD=$(shell pwd)
DATADIR=$(PWD)/data/
PYTHON-ENV=./virtualenv/uk
BIN=$(PYTHON-ENV)/bin/

DOC_IDS = $(shell seq -f "%03g" 40)

GSID := 1YHBlVC-0O0AcxQ2roglpCe7WuLO6IXrEtBuPq4zm7Jw
GSIDrecordings := 67250848
GSIDmergeRecordings := 541544278
GSIDmodify := 1296766099

MODEL_SIZE = tiny
MODEL_DEVICE = cpu

.ONESHELL:
SHELL := /bin/bash


######### AUDIO CROP AND RENAME

audio-help:
	@echo "generate missing questions:"
	@echo "    make audio-compile"
	@echo "add silents to original files:"
	@echo "    make audio-modify-orig"
	@echo "rename and crop:"
	@echo "    make audio-crop-rename"
	@echo "add silents,beeps + cropinside to (edge-)cropped files:"
	@echo "    (1/ modify content and 2/ crop inside)"
	@echo "    make audio-modify-cropped"
	@echo "merge host and guest tracks"
	@echo "    make audio-merge"

audio-compile: audio-compile-host11 audio-compile-host12
audio-compile-host11 audio-compile-host12:  audio-compile-host%: $(DATADIR)audio-merge.tsv
	@echo mkdir tmpQ0$*
	@echo cp $(DATADIR)/audio-source/Q0*.wav tmpQ0$*/
	@grep "Q0$*" $< | nl -n rz | sed "s/\([0-9]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\).*$$/sox tmpQ0$*\/\6 tmpQ0$*\/Q0$*.trim.\1.wav trim \7 =\8 \;\n sox tmpQ0$*\/Q0$*.trim.\1.wav tmpQ0$*\/Q0$*.pad.\1.wav pad \3 0/"
	@echo sox -m tmpQ0$*/Q0$*.pad.*.wav tmpQ0$*/Q0$*.result.wav
	#@echo cp tmpQ0$*/Q0$*.result.wav $(DATADIR)/audio-source/Ganna$*.WAV
	@echo sox -v 4.0 tmpQ0$*/Q0$*.result.wav $(DATADIR)/audio-source/Ganna$*.WAV


audio-crop-rename: $(DATADIR)audio-crop-rename.tsv
	for f in $(DATADIR)audio-source/*.m4a; do ffmpeg -i "$$f" -ar 44100 "$${f/%m4a/WAV}"; done
	grep "^1" $< | sed "s/\.m4a/\.WAV/"| sed "s@1\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\).*@sox $(DATADIR)/audio-source/\1 $(DATADIR)/audio-preprocessed/\3 trim \4 \=\5@"


audio-modify-orig: $(DATADIR)audio-silent-beep-orig.tsv # add silents and beeps
	@cat $^ \
	  | nl -n rz \
	  | sed "s@\([0-9]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\).*@mv $(DATADIR)/audio-source/\2 $(DATADIR)/audio-source/b\1.\2 \;\n  sox $(DATADIR)/audio-source/b\1.\2 $(DATADIR)/audio-source/w1.\1.\2 trim 0 =\5 pad 0 \7 \;\n  sox $(DATADIR)/audio-source/b\1.\2 $(DATADIR)/audio-source/w2.\1.\2 trim \6 \;\n  sox $(DATADIR)/audio-source/w1.\1.\2 $(DATADIR)/audio-source/w2.\1.\2 $(DATADIR)/audio-source/\2@"
audio-modify-cropped: $(DATADIR)audio-crop-beep-cropped.tsv # add silents and beeps
	# 1) add beeps
	grep -P "^[^\t]*\t0\t1" $< \
	  | nl -n rz \
	  | sed "s@\([0-9]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\).*@echo 'TODO BEEP \2 (\5 -- \6)'@"
	# 2) crop inside
	grep -P "^[^\t]*\t0\t-1" $< \
	  | sort -r -k4 \
	  | nl -n rz \
	  | sed "s@\([0-9]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\).*@cp $(DATADIR)/audio-preprocessed/\2 $(DATADIR)/audio-preprocessed/cB\1.\2 \;\n sox $(DATADIR)/audio-preprocessed/\2 $(DATADIR)/audio-preprocessed/part1.\2 trim 0 =\5 \;\n sox $(DATADIR)/audio-preprocessed/\2 $(DATADIR)/audio-preprocessed/part2.\2 trim \6 \;\n sox $(DATADIR)/audio-preprocessed/part1.\2 $(DATADIR)/audio-preprocessed/part2.\2 $(DATADIR)/audio-preprocessed/\2 \n@"



$(DATADIR)audio-merge.tsv:
	curl -L "https://docs.google.com/spreadsheets/d/$(GSID)/pub?gid=$(GSIDmergeRecordings)&single=true&output=tsv" \
	  > $@
$(DATADIR)audio-crop-rename.tsv:
	curl -L "https://docs.google.com/spreadsheets/d/$(GSID)/pub?gid=$(GSIDrecordings)&single=true&output=tsv" \
	  | grep -Pv "^\t" | grep -Pv "^0\t" > $@

$(DATADIR)audio-silent-beep-orig.tsv:
	curl -L "https://docs.google.com/spreadsheets/d/$(GSID)/pub?gid=$(GSIDmodify)&single=true&output=tsv" \
	  | grep -P "^[^\t]*\t1\t" > $@

$(DATADIR)audio-crop-beep-cropped.tsv:
	curl -L "https://docs.google.com/spreadsheets/d/$(GSID)/pub?gid=$(GSIDmodify)&single=true&output=tsv" \
	  | grep -P "^[^\t]*\t0\t" > $@


######### ASR

recognize-NN = $(addprefix recognize-, $(DOC_IDS))

recognize: $(recognize-NN)
$(recognize-NN): recognize-%: $(DATADIR)/recognize-working/CUNA_%
	mkdir -p "$(DATADIR)/recognize-working/" || :
	## test -f $(DATADIR)/audio-preprocessed/CUNA_$*.guest.wav && make recognize-double-$* || :
	test -f $(DATADIR)/audio-final/CUNA_$*.wav && make recognize-single-$* || :
	mkdir -p "$(DATADIR)/recognize/"
	cat "$(DATADIR)/recognize-working/CUNA_$*/CUNA_$*.whisper.segments.tsv" \
	  | sed '1 s@\(.*\t\)@\1<uk host topic000 text>@' > $(DATADIR)/recognize/CUNA_$*.tsv

recognize-dir-NN = $(addprefix $(DATADIR)/recognize-working/CUNA_, $(DOC_IDS))

$(recognize-dir-NN): %:
	mkdir -p $*


recognize-single_NN = $(addprefix recognize-single-, $(DOC_IDS))
$(recognize-single_NN): recognize-single-%:
	echo "INFO $*: recognize without annotating speaker"
	ln -s "../../audio-final/CUNA_$*.wav" "$(DATADIR)/recognize-working/CUNA_$*/CUNA_$*.wav"
	$(BIN)/python ./scripts/asr.py --dir "$(DATADIR)/recognize-working/CUNA_$*" \
	                               --speaker CUNA_$* \
	                               --model_size "$(MODEL_SIZE)"  \
	                               --model_device "$(MODEL_DEVICE)"  \
	                               --recognize whisper  \
	                               --model_params VAD DIS accurate  \
	                               --srt --tsv

recognize-double_NN = $(addprefix recognize-double-, $(DOC_IDS))
$(recognize-double_NN): recognize-double-%:
	echo "INFO $*: recognize host and guest and merge result"
	for t in 'host' 'guest'; do ln -s "../../audio-preprocessed/CUNA_$*.$${t}.wav" "$(DATADIR)/recognize-working/CUNA_$*/CUNA_$*.$${t}.wav" ; done
	$(BIN)/python ./scripts/asr.py --dir "$(DATADIR)/recognize-working/CUNA_$*" \
	                               --host CUNA_$*.host  \
	                               --guest CUNA_$*.guest  \
	                               --model_size "$(MODEL_SIZE)"  \
	                               --model_device "$(MODEL_DEVICE)"  \
	                               --recognize whisper  \
	                               --model_params VAD DIS accurate  \
	                               --merge CUNA_$*\
	                               --srt --tsv

slurm-recognize-NN = $(addprefix slurm-recognize-, $(DOC_IDS))
slurm-recognize: $(slurm-recognize-NN)
$(slurm-recognize-NN): slurm-recognize-%:
	mkdir -p "sbatch" || :
	mkdir -p "logs" || :
	echo '#!/bin/bash' > sbatch/CUNA$*
	echo '#SBATCH --output=logs/%x.%j.log' >> sbatch/CUNA$*
	echo '#SBATCH --ntasks=1' >> sbatch/CUNA$*
	echo '#SBATCH -p gpu-troja,gpu-ms' >> sbatch/CUNA$*
	echo '#SBATCH -q low' >> sbatch/CUNA$*
	echo '#SBATCH --mem=64G' >> sbatch/CUNA$*
	echo '#SBATCH --gres=gpu:1' >> sbatch/CUNA$*
	echo 'echo -e "$$(date +"%Y-%m-%dT%T")\tSTARTED\t$$SLURM_JOB_ID\t$$(hostname)\t--\t--" >> logs/CUNA.slurm.log' >> sbatch/CUNA$*
	echo '/usr/bin/time --output=logs/CUNA.slurm.$$SLURM_JOB_ID.tmp -f "%x\t%E real, %U user, %S sys, %M kB" make recognize-$* MODEL_SIZE=large MODEL_DEVICE=cuda' >> sbatch/CUNA$*
	echo 'TIME=$$(cut -f 2 logs/CUNA.slurm.$$SLURM_JOB_ID.tmp)' >> sbatch/CUNA$*
	echo 'CODE=$$(cut -f 1 logs/CUNA.slurm.$$SLURM_JOB_ID.tmp)' >> sbatch/CUNA$*
	echo 'rm logs/CUNA.slurm.$$SLURM_JOB_ID.tmp' >> sbatch/CUNA$*
	echo 'echo -e "$$(date +"%Y-%m-%dT%T")\t$$( [ "$$CODE" -gt "0" ] && echo "FAILED-$$CODE" || echo "FINISHED" )\t$$SLURM_JOB_ID\t$$(hostname)\t$$TIME\t--" >> logs/CUNA.slurm.log' >> sbatch/CUNA$*
	sbatch sbatch/CUNA$*

# DEV-ASR
dev-asr-medium:
	$(BIN)/python ./scripts/asr.py --dir SAMPLE1 --host Ganna1-00--60 --guest Interview1-00--60 --model_size medium --recognize whisper --model_params VAD DIS accurate --merge --srt --tsv

dev-asr-medium-skip-recognize:
	$(BIN)/python./scripts/asr.py --dir SAMPLE1 --host Ganna1-00--60 --guest Interview1-00--60 --recognized_host Ganna1-00--60.whisper-medium.json --recognized_guest Interview1-00--60.whisper-medium.json  --merge --srt --tsv


dev-asr-tiny:
	$(BIN)/python./scripts/asr.py --dir SAMPLE1 --host Ganna1-00--60 --guest Interview1-00--60 --model_size tiny --recognize whisper --model_params VAD DIS accurate --merge --srt --tsv
dev-asr-tiny-skip-recognize:
	$(BIN)/python./scripts/asr.py --dir SAMPLE1 --host Ganna1-00--60 --guest Interview1-00--60 --recognized_host Ganna1-00--60.whisper-tiny.json --recognized_guest Interview1-00--60.whisper-tiny.json  --merge --srt --tsv

dev-asr-wav2vec:
	$(BIN)/python./scripts/asr.py --dir SAMPLE1 --host Ganna1-00--60 --guest Interview1-00--60 --recognize wav2vec --merge --srt --tsv



######### AUDIO MERGE (host+guest channels)
audio-merge:
	for f in $(DATADIR)audio-preprocessed/CUNA_???.wav; do cp "$${f}" "$(DATADIR)audio-merged/$${f##*/}"; done
	for f in $(DATADIR)audio-preprocessed/CUNA_???.guest.wav; do sox -m "$${f}" "$${f/%guest.wav/host.wav}"  "$(DATADIR)audio-merged/$${f##*/}"; done
	rename "s/\.guest//" $(DATADIR)audio-merged/*.guest.wav
######### TRANSCRIPTION PROCESSING
## do manual transcription fixings + annotate languages and speakers

transcript-fix-prepare-NN = $(addprefix transcript-fix-prepare-, $(DOC_IDS))

transcript-fix-prepare: $(transcript-fix-prepare-NN)
$(transcript-fix-prepare-NN): transcript-fix-prepare-%: $(DATADIR)/transcript-fix-input/CUNA_%
	cat $(DATADIR)/recognize/CUNA_$*.tsv \
	  | sed 's/\t/000000\t/g' \
	  | sed -e 's/\(\.[0-9][0-9][0-9][0-9][0-9][0-9]\)0*\t/\1\t/g' \
	  > $(DATADIR)/transcript-fix-input/CUNA_$*/CUNA_$*.txt
	touch $(DATADIR)/transcript-fix-input/CUNA_$*/CUNA_$*-audio.txt
	lame -b 64 $(DATADIR)/audio-merged/CUNA_$*.wav $(DATADIR)/transcript-fix-input/CUNA_$*/CUNA_$*.mp3


transcript-fix-in-dir-NN = $(addprefix $(DATADIR)/transcript-fix-input/CUNA_, $(DOC_IDS))

$(transcript-fix-in-dir-NN): %:
	mkdir -p $*

## transcript-validate - check if transcriptions are in correct format

transcript-validate-NN = $(addprefix transcript-validate-, $(DOC_IDS))
transcript-validate: $(transcript-validate-NN)
$(transcript-validate-NN): transcript-validate-%: $(DATADIR)/transcript-fix-output/CUNA_%
	@echo "INFO: validating transcription $*"
	cat $</CUNA_$*.txt | grep -Pv '^$$'|grep -Pv '^[0-9]+\.[0-9]+\t[0-9]+\.[0-9]+\t[^\t]+$$' && echo "ERROR: $* invalid tab format" || :
	nl -n ln $</CUNA_$*.txt | sed -n 's/\t.*\t/\t/p' | perl -pe 's/([\t\>\]])[^\[\<\]\>\n]*?([^\[\<\]\>\n ])[^\[\<\]\>\n]*/\1\2/g' \
	  | perl -pe 's/([\t\>\]])[^\t\>\]\<\[]/\1#/g' > $<.tmp
	cat $<.tmp | sed -ne 's/^\([0-9]*\)\t[^#]*$$/\1/p' > $<.tmp.line-no-text
	cat $<.tmp | grep -P '#.*[\<\[][a-z0-9 ]*(host|guest|topic[0-9]*)' | sed -e 's/\t.*$$//' > $<.tmp.line-inside-sentence
	cat $<.tmp | grep -Pv '[0-9]*\t(#|<[a-z0-9 ]*>|\[[a-z0-9 ]*\])*$$' | sed -e 's/\t.*$$//' > $<.tmp.line-format
	LINES=`cat $<.tmp.line-*|sort|uniq|sed "s/$$/p\;/"|tr -d "\n"` ;nl -n ln  $</CUNA_$*.txt | sed "$${LINES}d"|sed 's/^/ERROR in $* on line /'
	cat $<.tmp | grep -Po '[\<\[][a-z0-9 ]*[\]\>]'|tr -d '[]<>'|tr ' ' '\n'|sort|uniq|grep -vP '^(host|guest|topic\d\d\d|beep|text|uk|ru|sl|en)$$' >  $<.tmp.unknown-cat
	CAT=`cat $<.tmp.unknown-cat|sed "s/^\(..*\)$$/\/\1\/p\;/"|tr -d "\n"` ;nl -n ln $</CUNA_$*.txt | sed -n "$${CAT}"|sed 's/^/ERROR CATEGORY in $* on line /'
	echo "INFO: " `cat $<.tmp.* | wc -l` " errors in $*"
	rm $<.tmp*




## transcript-and-postprocess fix audio and shift timestamps

transcript-and-audio-postprocess-NN = $(addprefix transcript-and-audio-postprocess-, $(DOC_IDS))
transcript-and-audio-postprocess: $(transcript-and-audio-postprocess-NN)
$(transcript-and-audio-postprocess-NN): transcript-and-audio-postprocess-%: transcript-postprocess-% audio-postprocess-%

transcript-postprocess-NN = $(addprefix transcript-postprocess-, $(DOC_IDS))
transcript-postprocess: $(transcript-postprocess-NN)
$(transcript-postprocess-NN): transcript-postprocess-%:
	echo "INFO: shifting times in % transcription"
	echo "TODO $@"

audio-postprocess-NN = $(addprefix audio-postprocess-, $(DOC_IDS))
audio-postprocess: $(audio-postprocess-NN)
$(audio-postprocess-NN): audio-postprocess-%:
	echo "INFO: adding beeps to % audio"
	echo "INFO: shifting times in % audio"
	echo "TODO $@"

## convert to TEI

## annotate with UDPipe and NameTag

## finalize TEI format - make corpus, add taxonomies, fill metadata

## convert to derived formats


######### SETUP

python-env-activate:
	. $(PYTHON-ENV)/bin/activate

$(PYTHON-ENV)/bin/activate:
	@test -f $(PYTHON-ENV)/bin/activate || make setup-python-env
setup-python-env:
	mkdir -p `echo -n "$(PYTHON-ENV)"|sed 's#/$$##' |sed 's#[^/]*$$##'`
	python -m venv $(PYTHON-ENV)
	. $(PYTHON-ENV)/bin/activate \
	&& pip install --upgrade pip \
	&& pip install --upgrade pip git+https://github.com/huggingface/transformers.git accelerate datasets[audio] \
	&& pip install --upgrade openai-whisper  whisper-timestamped pydub auditok