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
    rows += ['', f'В группах {sum(len(g["files"]) for g in groups.values())} записей, {len(groups)} групп. Источники обозначены историческими именами; WAV удалены по запросу владельца, в игре остаются OGG.', '',
             '## Действия и состояния', '', '| Вид / действие | Группы альтернатив | Вероятность голоса | Голосовых записей | Исходов, включая тишину |', '|---|---|---:|---:|---:|']
    for species,actions in profiles.items():
        for action,(prob,events) in actions.items():
            n=sum(counts[event] for event in events)
            rows.append(f"| {species.removeprefix('growl_')} / {action} | {' / '.join(events)} | {prob:.0%} | {n} | {n+int(prob<1)} |")
    rows += ['', 'Fours применяется к Hunger на четвереньках; голос hunger_fours_voice используется только в этой позе, а не в обычной стойке. Agony запускается только вместе с успешным стартом Agonize. Feeding звучит после BiteDown, с интервалом 2,4–3,2 с и прекращается при подъёме, тревоге, потере ноги или смерти. Idle scream не вызывает тревогу.', '',
             '## Комбинации конкретного действия', '',
             'У атаки отдельно выбираются замах, необязательный голос и звук контакта. Таблица считает завершённую атаку с контактом; при промахе звука контакта нет. Pain всегда содержит flesh_hit, голос добавляется с вероятностью 35%. Death — один видовой звук, для остальных enemy_death. Не считаются pitch, задержки, разрыв конечности и особые умения — это отдельные события.', '',
             '| Вид | Замах × (голос или тишина) × удар | Замах × (голос или тишина) × укус | Получение урона | Смерть |', '|---|---:|---:|---:|---:|']
    for species in ['hunger','revenant','zombie','brute','titan','colossus','horde']:
        key='growl_'+species
        profile=profiles.get(key,{})
        attack=profile.get('attack',(.5,[key]))
        pain=profile.get('pain',(.35,[key]))
        a=sum(counts[e] for e in attack[1])+1
        p=sum(counts[e] for e in pain[1])+1
        death=profile.get('death',(1.,['enemy_death']))
        d=sum(counts[e] for e in death[1])
        rows.append(f"| {species} | {counts['attack_swing']*a*counts['attack_hit']} | {counts['attack_swing']*a*counts['attack_bite']} | {counts['flesh_hit']*p} | {d} |")
    rows += ['', 'Scream_zombie и прежняя группа roar_heavy удалены. Первое обнаружение использует hunger_alert или голос своего вида. roar_heavy_4 перенесён в colossus_voice для обычной речи Colossus. Каждая строка контакта применима только когда данный способ атаки поддерживается видом; таблица не добавляет новые атаки.', '',
              '## Добавление записей', '', '1. Конвертировать запись в моно OGG Vorbis q5/48 кГц и проверить декодирование; после проверки удалить WAV и его import.', '2. Использовать путь sfx/<event>/<event>_<index>.ogg, обновить EVENTS и enemy_voice_groups.json.', '3. Для новой группы добавить действие в enemy_voice_profile.gd, затем выполнить генератор и профильные тесты.', '', 'tools/import_audio_refresh.py воспроизводит замену из исходного коммита 0e154b73. Старый build_added_audio.py описывает предыдущий импорт с исходниками; текущую папку им не пересобирать.', '']
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
