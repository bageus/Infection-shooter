#!/usr/bin/env python3
"""Import the owner's 2026-10-26 weapon, door and pickup recordings.

Converts each WAV to mono Vorbis under its event folder, deletes the old
variants it replaces and the verified WAV, and records the conversion in
assets/audio/audio_refresh_processing.json (which also protects the events
from the generators). Run from tools/: python import_weapon_audio.py
"""
import hashlib
import json
import subprocess
from pathlib import Path

from build_added_audio import ROOT, convert

SFX = ROOT / 'assets/audio/sfx'
# source wav (relative to sfx) -> output stem (relative to sfx)
IMPORTS = {
    'weapon_pickup/the_shutter_clicked': 'dry_fire/dry_fire_1',
    'weapon_pickup/weapon_pickup': 'weapon_pickup/weapon_pickup_1',
    'weapon_pickup/changing_weapon': 'weapon_switch/weapon_switch_1',
    'm4_reload/m4_reload': 'm4_reload/m4_reload_1',
    'ak_reload/AK_reload': 'ak_reload/ak_reload_1',
    'uzi_reload/uzi_reload': 'uzi_reload/uzi_reload_1',
    'pistol_reload/pistols_reload': 'pistol_reload/pistol_reload_1',
    'launcher_reload/grenade_louncher_reloded': 'launcher_reload/launcher_reload_1',
    'sniper_reload/sniper_reload': 'sniper_reload/sniper_reload_1',
    'shotgun_shell_load/shutgun_reload_1': 'shotgun_shell_load/shotgun_shell_load_1',
    'shotgun_shell_load/shutgun_reload_2': 'shotgun_shell_load/shotgun_shell_load_2',
    'shotgun_shell_load/shutgun_reload_3': 'shotgun_pump/shotgun_pump_1',
    'pistol_fire/pistol_desert_attack': 'pistol_fire/pistol_fire_1',
    'ak_fire/AK74_attack': 'ak_fire/ak_fire_1',
    'm4_fire/m4_attack': 'm4_fire/m4_fire_1',
    'shotgun_fire/shotgun_attack': 'shotgun_fire/shotgun_fire_1',
    'uzi_fire/Uzi_firing_rapidly': 'uzi_fire/uzi_fire_1',
    'launcher_fire/grenade_launcher_att': 'launcher_fire/launcher_fire_1',
    'door_open/door_open_boots': 'door_open/door_open_1',
    'door_open/door_closed': 'door_close/door_close_1',
    'casing_heavy/casing_heavy_dropped_1': 'casing_heavy/casing_heavy_1',
    'casing_heavy/casing_heavy_dropped_2': 'casing_heavy/casing_heavy_2',
    'casing_brass/casing_brass_droped': 'casing_brass/casing_brass_1',
    'casing_shell/casing_shotgun_dropp': 'casing_shell/casing_shell_1',
    'casing_launcher/casing_grenade_launc': 'casing_launcher/casing_launcher_1',
    'ammo_pickup/ammo_pickup': 'ammo_pickup/ammo_pickup_1',
}
# Old variants that have no new recording; their events now have fewer variants.
DELETE = [f'casing_brass/casing_brass_{i}' for i in range(2, 9)] + [
    'casing_heavy/casing_heavy_3', 'casing_shell/casing_shell_2', 'casing_shell/casing_shell_3',
    'casing_shell/casing_shell_4', 'shotgun_shell_load/shotgun_shell_load_3',
    'shotgun_shell_load/shotgun_shell_load_4', 'weapon_pickup/weapon_pickup_2', 'weapon_switch/weapon_switch_2',
    'ak_fire/ak_fire_2', 'ak_fire/ak_fire_3', 'm4_fire/m4_fire_2', 'm4_fire/m4_fire_3',
    'pistol_fire/pistol_fire_2', 'pistol_fire/pistol_fire_3', 'uzi_fire/uzi_fire_2', 'uzi_fire/uzi_fire_3',
    'uzi_fire/uzi_fire_4', 'shotgun_fire/shotgun_fire_2', 'shotgun_fire/shotgun_fire_3', 'launcher_fire/launcher_fire_2',
    'pistol_reload/pistol_reload_2', 'pistol_reload/pistol_reload_3', 'uzi_reload/uzi_reload_2',
    'launcher_reload/launcher_reload_2', 'door_open/door_open_2', 'ammo_pickup/ammo_pickup_2', 'dry_fire/dry_fire_2',
]


def unlink(stem):
    for suffix in ('.ogg', '.ogg.import', '.wav', '.wav.import'):
        Path(str(SFX / stem) + suffix).unlink(missing_ok=True)


def main():
    receipt_path = ROOT / 'assets/audio/audio_refresh_processing.json'
    receipt = json.loads(receipt_path.read_text())
    outputs = {'assets/audio/sfx/' + stem + '.ogg' for stem in IMPORTS.values()}
    receipt['records'] = [r for r in receipt['records'] if r['output'] not in outputs]
    for source, stem in IMPORTS.items():
        wav, target = SFX / (source + '.wav'), SFX / (stem + '.ogg')
        record = convert(wav, target, mono=True)
        record['source_sha256'] = hashlib.sha256(wav.read_bytes()).hexdigest()
        record['output_sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(target), '-f', 'null', '-'], check=True)
        receipt['records'].append(record)
        unlink(source)
    for stem in DELETE:
        unlink(stem)
    receipt_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
    print(f'Converted {len(IMPORTS)} recordings, removed {len(DELETE)} old variants.')


if __name__ == '__main__':
    main()
