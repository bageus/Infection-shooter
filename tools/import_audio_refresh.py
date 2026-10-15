#!/usr/bin/env python3
"""Import the owner's 2026-10-15 refresh, then remove verified WAV sources.

Run against source commit 0e154b73. Existing OGG music is kept byte-for-byte.
The processing receipt retains source hashes after the requested WAV removal.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from build_added_audio import ROOT, convert, import_settings

RENAMES = {
    'extinguisher_burst/fire_extinguisher_boom': 'extinguisher_burst/extinguisher_burst_1',
    'extinguisher_burst/fire_extinguisher_fell': 'extinguisher_fall/extinguisher_fall_1',
    'skill_alive/Done_alive': 'skill_second_heart/skill_second_heart_1',
    'skill_colldown_done/Sci-fi_metal_pop_sou': 'skill_cooldown_done/skill_cooldown_done_1',
    'colossus&titan_death/colossus&titan_death_1': 'heavy_death/heavy_death_1',
    'ak_reload/ak_reload': 'ak_reload/ak_reload_1',
    'm4_reload/m4_reload': 'm4_reload/m4_reload_1',
    'sniper_reload/sniper_reload': 'sniper_reload/sniper_reload_1',
}
REPLACED = ['extinguisher_burst/extinguisher_burst_2', 'horde_summon/horde_summon_2',
            'door_close/door_close_2', 'key_pickup/key_pickup_2',
            'canister_drop/canister_drop_1', 'canister_drop/canister_drop_2',
            'canister_drop/canister_drop_3']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify the committed receipt without source WAVs')
    if parser.parse_args().check:
        receipt = json.loads((ROOT/'assets/audio/audio_refresh_processing.json').read_text())
        for row in receipt['records']:
            target = ROOT/row['output']
            assert hashlib.sha256(target.read_bytes()).hexdigest() == row['output_sha256'], target
            subprocess.run(['ffmpeg', '-v', 'error', '-i', str(target), '-f', 'null', '-'], check=True)
            assert not (ROOT/row['source']).exists(), row['source']
        assert not list((ROOT/'assets/audio').rglob('*.wav'))
        assert not list((ROOT/'assets/audio').rglob('*.wav.import'))
        print(f"Verified {len(receipt['records'])} conversions; no WAV sources or orphan WAV imports.")
        return
    sfx = ROOT/'assets/audio/sfx'
    sources = sorted(sfx.rglob('*.wav'))
    assert len(sources) == 30, f'Expected 30 refresh WAVs, found {len(sources)}'
    groups_path = ROOT/'assets/audio/enemy_voice_groups.json'
    groups = json.loads(groups_path.read_text())
    records = []
    for source in sources:
        key = source.relative_to(sfx).with_suffix('').as_posix()
        target = sfx/(RENAMES.get(key, key) + '.ogg')
        record = convert(source, target, loop=key.startswith('minigun_spin/'), mono=True)
        record['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
        record['output_sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
        # Decode the final file before deleting the source.
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(target), '-f', 'null', '-'], check=True)
        records.append(record)
        group = target.parent.name
        if group.startswith(('hunger_', 'revenant_', 'colossus_', 'titan_', 'horde_idle', 'heavy_death')):
            row = groups.setdefault(group, {'files': [], 'sources': []})
            path = 'res://' + target.relative_to(ROOT).as_posix()
            if path not in row['files']:
                row['files'].append(path)
                row['sources'].append(source.stem)
        source.unlink()
        Path(str(source)+'.import').unlink(missing_ok=True)
    # Only the fourth heavy roar survives, as a Colossus speaking voice.
    roar = sfx/'roar_heavy/roar_heavy_4.ogg'
    voice = sfx/'colossus_voice/colossus_voice_1.ogg'
    voice.parent.mkdir(exist_ok=True)
    shutil.move(roar, voice)
    Path(str(roar)+'.import').unlink(missing_ok=True)
    import_settings(voice, False)
    groups['colossus_voice'] = {'files': ['res://assets/audio/sfx/colossus_voice/colossus_voice_1.ogg'], 'sources': ['roar_heavy_4']}
    groups['titan_idle'] = {'files': [f'res://assets/audio/sfx/titan_idle/titan_idle_{i}.ogg' for i in (1, 2)], 'sources': ['titan_idle_1', 'titan_idle_2']}
    for key in REPLACED:
        path = sfx/(key+'.ogg')
        path.unlink(missing_ok=True)
        Path(str(path)+'.import').unlink(missing_ok=True)
    # Music has already been converted and processed by ADR-0048.
    for source in (ROOT/'assets/audio/music').glob('*.wav'):
        key = source.stem.lower().replace(' ', '_')
        target = source.with_name(key+'.ogg')
        assert target.exists(), target
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(target), '-f', 'null', '-'], check=True)
        source.unlink()
        Path(str(source)+'.import').unlink(missing_ok=True)
    groups_path.write_text(json.dumps(groups, ensure_ascii=False, indent=2)+'\n')
    receipt = {'source_commit': '0e154b73', 'records': records, 'wav_sources_removed': True}
    (ROOT/'assets/audio/audio_refresh_processing.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n')
    print(f'Converted and verified {len(records)} WAVs; removed source WAVs and replaced variants.')


if __name__ == '__main__':
    main()
