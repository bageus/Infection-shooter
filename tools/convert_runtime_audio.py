#!/usr/bin/env python3
"""Convert owner WAV additions to verified mono Vorbis, then remove originals.

--check verifies the receipt, decodes outputs and rejects runtime PCM/WAV.
The named roll recording can be imported later without changing gameplay code.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from build_added_audio import ROOT, convert

RECEIPT = ROOT / 'assets/audio/glass_audio_processing.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check():
    rows = json.loads(RECEIPT.read_text())['records']
    for row in rows:
        target = ROOT / row['output']
        assert digest(target) == row['output_sha256'], target
        assert not (ROOT / row['source']).exists(), row['source']
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(target), '-f', 'null', '-'], check=True)
    assert not [p for p in (ROOT / 'assets').rglob('*') if p.suffix.lower() == '.wav']
    assert not list((ROOT / 'assets').rglob('*.wav.import'))
    for path in (ROOT / 'game').rglob('*.gd'):
        text = path.read_text()
        if 'tests' not in path.parts:
            assert 'AudioStreamWAV' not in text and '.wav"' not in text, path
    for path in (ROOT / 'assets/audio').rglob('*.tres'):
        assert 'AudioStreamWAV' not in path.read_text(), path
    # Vorbis block padding differs between reversed transients; compare decoded
    # waveforms with alignment instead of requiring byte-identical lossy PCM.
    import numpy as np
    def decode(name):
        raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i',
               str(ROOT / 'assets/audio/ui' / (name + '.ogg')), '-ar', '22050',
               '-ac', '1', '-f', 'f32le', '-'])
        return np.frombuffer(raw, dtype='<f4')
    for first, second in [('mutation_open', 'mutation_close'), ('mutation_lock', 'mutation_unlock')]:
        a, b = decode(first), decode(second)[::-1]
        lag = int(np.correlate(a, b, mode="full").argmax()) - len(b) + 1
        assert abs(lag) <= 512, (first, lag)
        start_a, start_b = max(lag, 0), max(-lag, 0)
        count = min(len(a) - start_a, len(b) - start_b)
        assert count > min(len(a), len(b)) * 0.8
        similarity = float(np.corrcoef(a[start_a:start_a + count], b[start_b:start_b + count])[0, 1])
        assert similarity > 0.95, (first, similarity)
    print(f'Verified {len(rows)} owner conversions, reverse cues and OGG-only runtime.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    if parser.parse_args().check:
        check()
        return
    records = json.loads(RECEIPT.read_text())['records'] if RECEIPT.exists() else []
    sfx = ROOT / 'assets/audio/sfx'
    sources = sorted(p for p in (ROOT / 'assets/audio').rglob('*') if p.suffix.lower() == '.wav')
    for source in sources:
        name = source.stem.lower()
        if name.startswith('the_crunch_of_glass__'):
            number = int(name.rsplit('_', 1)[1])
            assert number in range(1, 5)
            target = sfx / f'step_glass/step_glass_{number}.ogg'
        elif name == 'the_heavy_character_1':
            target = sfx / 'player_roll/player_roll_1.ogg'
        else:
            target = source.with_suffix('.ogg')
        assert not target.exists(), f'Refusing to overwrite existing audio: {target}'
        original_hash = digest(source)
        row = convert(source, target, mono=True)
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(target), '-f', 'null', '-'], check=True)
        row.update(source_sha256=original_hash, output_sha256=digest(target))
        records.append(row)
        RECEIPT.write_text(json.dumps({'records': records}, indent=2) + '\n')
        source.unlink()
        Path(str(source) + '.import').unlink(missing_ok=True)
    print(f'Converted {len(sources)} WAV sources; receipt has {len(records)} verified records.')


if __name__ == '__main__':
    main()
