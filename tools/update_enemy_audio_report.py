#!/usr/bin/env python3
"""Generate an exact finite recording-combination report from runtime profiles."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT/'docs/ENEMY_AUDIO_GROUPS.md'


def generate():
    catalogue = (ROOT/'game/core/audio/public/sound_events.gd').read_text()
    counts = {name:int(n) for name,n in re.findall(r'&"([^"]+)": \[(\d+),',catalogue)}
    profiles = {}
    species = None
    for line in (ROOT/'game/features/infected/enemy_voice_profile.gd').read_text().splitlines():
        match = re.search(r'&"(growl_[^"]+)": \{',line)
        if match:
            species = match[1]
            profiles[species]={}
        action = re.search(r'&"([^"]+)": \[([\d.]+), \[(.*?)\]\]',line)
        if action:
            name,prob,events=action.groups()
            profiles[species][name]=(float(prob),re.findall(r'&"([^"]+)"',events))
    groups=json.loads((ROOT/'assets/audio/enemy_voice_groups.json').read_text())
    rows=['# Группы звуков заражённых', '', 'Автоматически: `python tools/update_enemy_audio_report.py`. Проверка актуальности: `--check`.', '',
          'Вариант = отдельная запись. Выбор из группы альтернативный: несколько голосов одновременно не наслаиваются. Микроизменения высоты и громкости не считаются новыми комбинациями. Вероятности относятся к попытке воспроизведения; бюджет голосов и уже звучащая речь могут её пропустить.', '',
          '## Добавленные группы', '', '| Группа | Файлов / вариантов | Исходные записи |', '|---|---:|---|']
    for name,group in groups.items():
        actual=list((ROOT/f'assets/audio/sfx/{name}').glob('*.ogg'))
        assert len(actual)==counts[name]==len(group['files']), name
        rows.append(f"| {name} | {counts[name]} | {', '.join(group['sources'])} |")
    rows += ['', 'В каждой группе выбирается одна запись, поэтому количество одиночных звуковых комбинаций равно числу файлов. Сейчас 10 новых записей в 9 группах. Соседние OGG рядом с WAV — конвертированные оригиналы; копии в группах — те же записи и повторно не считаются.', '',
             '## Действия и состояния', '', '| Вид / действие | Группы альтернатив | Вероятность голоса | Голосовых записей | Исходов, включая тишину |', '|---|---|---:|---:|---:|']
    for species,actions in profiles.items():
        for action,(prob,events) in actions.items():
            n=sum(counts[event] for event in events)
            rows.append(f"| {species.removeprefix('growl_')} / {action} | {' / '.join(events)} | {prob:.0%} | {n} | {n+int(prob<1)} |")
    rows += ['', 'Fours применяется к Hunger на четвереньках; голос hunger_fours_voice используется только в этой позе, а не в обычной стойке. Agony запускается только вместе с успешным стартом Agonize. Feeding звучит после BiteDown, с интервалом 2,4–3,2 с и прекращается при подъёме, тревоге, потере ноги или смерти. Idle scream не вызывает тревогу.', '',
             '## Комбинации конкретного действия', '',
             'У атаки отдельно выбираются замах, необязательный голос и звук контакта. Таблица считает завершённую атаку с контактом; при промахе звука контакта нет. Pain всегда содержит flesh_hit, голос добавляется с вероятностью 35%. Death — один enemy_death. Не считаются pitch, задержки, разрыв конечности и особые умения — это отдельные события.', '',
             '| Вид | Замах × (голос или тишина) × удар | Замах × (голос или тишина) × укус | Получение урона | Смерть |', '|---|---:|---:|---:|---:|']
    for species in ['hunger','revenant','zombie','brute','titan','colossus','horde']:
        key='growl_'+species
        profile=profiles.get(key,{})
        attack=profile.get('attack',(.5,[key]))
        pain=profile.get('pain',(.35,[key]))
        a=sum(counts[e] for e in attack[1])+1
        p=sum(counts[e] for e in pain[1])+1
        rows.append(f"| {species} | {counts['attack_swing']*a*counts['attack_hit']} | {counts['attack_swing']*a*counts['attack_bite']} | {counts['flesh_hit']*p} | {counts['enemy_death']} |")
    rows += ['', 'Остальные виды используют прежние growl_* / scream_zombie / roar_heavy. Каждая строка контакта применима только когда данный способ атаки поддерживается видом; таблица не добавляет новые атаки.', '',
             '## Добавление записей', '', '1. Положить WAV в zombie_misc, внести имя в GROUPS в tools/build_added_audio.py.', '2. Запустить конвертацию. Оригиналы не меняются. Отдельные синтетические варианты не создаются.', '3. Увеличить число вариантов соответствующего события в sound_events.gd; при новой группе добавить профиль действия в enemy_voice_profile.gd.', '4. Выполнить этот генератор и тесты sound_event, adaptive_audio, enemy_voice.', '', 'Группы повреждения и смерти пока используют существующие записи; добавлять новую специфическую запись следует в соответствующий профиль, без случайного смешения видов.', '']
    return '\n'.join(rows)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    text=generate()
    if args.check:
        assert REPORT.read_text()==text, 'Stale audio report; regenerate it'
    else:
        REPORT.write_text(text)
    print('Enemy audio groups and combinations verified.')


if __name__=='__main__':
    main()
