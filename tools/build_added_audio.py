#!/usr/bin/env python3
"""Historical 2026-10-15 WAV import; do not run against the refreshed project.

Requires --historical-import and a pre-refresh checkout with original WAVs.
Current OGG/voice groups must never be replaced by this old group catalogue.
convert/import_settings remain available to the historical refresh importer.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000
GROUPS = {
    'hunger_idle': ['the_cry_of_a_person_3'],
    'hunger_voice': ['the_scream_of_an_inf_1'],
    'hunger_fours_voice': ['the_scream_of_an_inf_4'],
    'hunger_alert': ['sounds_of_zombies_ta_2'],
    'hunger_attack': ['the_scream_of_an_inf_2', 'sounds_of_zombies_ta_3'],
    'hunger_agony': ['the_scream_of_an_inf_22'],
    'hunger_feeding': ['zombie_damage_sounds_4'],
    'revenant_voice': ['the_scream_of_an_inf_3'],
    'revenant_attack': ['sounds_of_zombies_ta_4'],
}

def import_settings(path, loop):
    sidecar = Path(str(path) + '.import')
    if sidecar.exists():
        import re
        text = sidecar.read_text()
        sidecar.write_text(re.sub(r'loop=(true|false)', 'loop='+str(loop).lower(), text))
        return
    res = 'res://' + path.relative_to(ROOT).as_posix()
    dest = 'res://.godot/imported/' + path.name + '-' + hashlib.md5(res.encode()).hexdigest() + '.oggvorbisstr'
    Path(str(path) + '.import').write_text(f'''[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"
path="{dest}"

[deps]

source_file="{res}"
dest_files=["{dest}"]

[params]

loop={str(loop).lower()}
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
''')

def convert(source, destination, loop=False, trim=0., mono=False):
    channels = 1 if mono else 2
    raw = subprocess.check_output(['ffmpeg','-v','error','-i',str(source),'-f','f32le','-ar',str(RATE),'-ac',str(channels),'-'])
    samples = np.frombuffer(raw, dtype='<f4').reshape(-1, channels).copy()
    source_frames = len(samples)
    samples = samples[:len(samples) - round(trim * RATE)]
    overlap = round(.08 * RATE) if loop else 0
    if loop:
        t = np.linspace(0, 1, overlap)[:,None]
        seam = samples[-overlap:] * (1-t) + samples[:overlap] * t
        samples = np.concatenate((samples[overlap:-overlap], seam))
    else:
        fade = min(round(.005 * RATE), len(samples)//4)
        samples[:fade] *= np.linspace(0,1,fade)[:,None]
        samples[-fade:] *= np.linspace(1,0,fade)[:,None]
    peak = float(np.max(np.abs(samples)))
    samples *= min(1., .89 / max(peak, .0001))
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Encode outside the project, so an editor cannot import a partially written OGG.
    with tempfile.TemporaryDirectory(dir=ROOT.parent, prefix='audio_encode_') as temporary:
        output = Path(temporary)/destination.name
        subprocess.run(['ffmpeg','-v','error','-y','-f','f32le','-ar',str(RATE),'-ac',str(channels),'-i','-','-c:a','libvorbis','-q:a','5',str(output)], input=samples.astype('<f4').tobytes(), check=True)
        seconds = float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',str(output)]))
        assert abs(seconds-len(samples)/RATE) < .01, f'Truncated conversion: {source}'
        output.replace(destination)
    import_settings(destination, loop)
    return {'source': str(source.relative_to(ROOT)), 'output': str(destination.relative_to(ROOT)), 'source_seconds': source_frames / RATE, 'trim_end_seconds': trim, 'overlap_seconds': overlap/RATE, 'output_seconds': len(samples)/RATE, 'channels': channels, 'loop':loop, 'seam_step': float(np.max(np.abs(samples[0]-samples[-1]))) if loop else None}

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--historical-import", action="store_true")
    args = parser.parse_args(argv)
    if not args.historical_import or (ROOT / "assets/audio/audio_refresh_processing.json").exists():
        parser.error("Historical importer disabled: use a pre-refresh checkout with original WAVs; current OGG and voice groups are protected")
    music = ROOT / 'assets/audio/music'
    records=[]
    for name, target, trim in [('main menu','main_menu',0.),('menu from game','menu_from_game',1.),('Server_Oper','server_oper',0.),('Seamless_Loop','seamless_loop',0.),('Tower_Hunt','tower_hunt',0.),('music_cinematic_boom','music_cinematic_boom',0.)]:
        records.append(convert(music/(name+'.wav'),music/(target+'.ogg'),target!='music_cinematic_boom',trim))
    fan = ROOT/'assets/audio/sfx/coller_server'
    records.append(convert(fan/'sound_of_server_oper.wav',fan/'sound_of_server_oper.ogg',True,.3,True))
    misc = ROOT/'assets/audio/sfx/zombie_misc'
    for source in sorted(misc.glob('*.wav')):
        records.append(convert(source,source.with_suffix('.ogg'),mono=True))
    catalogue={}
    for group, files in GROUPS.items():
        paths=[]
        for i, name in enumerate(files,1):
            target=ROOT/f'assets/audio/sfx/{group}/{group}_{i}.ogg'
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(misc/(name+'.ogg'),target)
            import_settings(target,False)
            paths.append('res://'+target.relative_to(ROOT).as_posix())
        catalogue[group]={'files':paths,'sources':files}
    (ROOT/'assets/audio/enemy_voice_groups.json').write_text(json.dumps(catalogue,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'assets/audio/added_audio_processing.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    print(f'Converted {len(records)} originals; {len(catalogue)} groups. WAV originals preserved.')

if __name__=='__main__':
    main()
