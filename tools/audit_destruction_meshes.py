#!/usr/bin/env python3
"""Rank authored destruction-stage mesh nodes; source data only, not FPS."""
from __future__ import annotations
import argparse
import json
import subprocess
from pathlib import Path
from check_model_textures import ROOT, active, read_glb

STAGES = {'modular', 'door_off', 'largeparts', 'smallfragments', 'jaggedfragments',
          'plantdestroyed', 'potfragments', 'broken_7', 'fragments', 'primary',
          'panels', 'medium', 'fine', 'topsecondary', 'damageready', 'glass_shards'}


def stage_name(name: str) -> bool:
    return name.lower().split('.', 1)[0] in STAGES


def descendants(document: dict, roots: list[int]) -> set[int]:
    seen = set()
    pending = list(roots)
    while pending:
        index = pending.pop()
        if index in seen:
            continue
        seen.add(index)
        pending.extend(document['nodes'][index].get('children', []))
    return seen


def counts(document: dict, indices: set[int]) -> tuple[int, int]:
    instances = triangles = 0
    for index in indices:
        node = document['nodes'][index]
        if 'mesh' not in node:
            continue
        instances += 1
        for primitive in document['meshes'][node['mesh']].get('primitives', []):
            accessor = primitive.get('indices', primitive['attributes'].get('POSITION'))
            count = document['accessors'][accessor]['count'] if accessor is not None else 0
            mode = primitive.get('mode', 4)
            triangles += count // 3 if mode == 4 else max(0, count - 2) if mode in (5, 6) else 0
    return instances, triangles


def audit(document: dict, path: str, placements: int = 0) -> dict:
    roots = [index for scene in document.get('scenes', []) for index in scene.get('nodes', [])]
    attached = descendants(document, roots)
    stage_rows = {}
    for index in sorted(attached):
        name = document['nodes'][index].get('name', '')
        if stage_name(name):
            mesh_count, triangles = counts(document, descendants(document, [index]))
            stage_rows[name] = {'meshes': mesh_count, 'triangles': triangles}
    for scene in document.get('scenes', []):
        name = scene.get('name', '')
        if stage_name(name):
            mesh_count, triangles = counts(document, descendants(document, scene.get('nodes', [])))
            stage_rows[name] = {'meshes': mesh_count, 'triangles': triangles}
    total, triangles = counts(document, attached)
    peak = max((x['meshes'] for x in stage_rows.values()), default=0)
    return {'path': path, 'source_mesh_nodes': total, 'source_triangles': triangles,
            'stages': stage_rows, 'largest_stage_meshes': peak,
            'base_map_placements': placements, 'stage_meshes_times_placements': peak * placements}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, default=ROOT / 'docs/qa/destruction_model_rework.md')
    parser.add_argument('--json', type=Path, default=ROOT / 'docs/qa/destruction_model_rework.json')
    args = parser.parse_args()
    base = json.loads((ROOT / 'game/presentation/office_floor/public/base_office_map.json').read_text())
    placements = {}
    for record in base['objects']:
        key = str(record.get('scene', '')).removeprefix('res://')
        placements[key] = placements.get(key, 0) + 1
    paths = subprocess.check_output(['git', 'ls-files', '*.glb'], cwd=ROOT, text=True).splitlines()
    rows = []
    for path in paths:
        if not path.startswith('models/objects/enviroments/') or not active(ROOT / path):
            continue
        document, _ = read_glb(ROOT / path)
        rows.append(audit(document, path, placements.get(path, 0)))
    rows.sort(key=lambda x: (x['stage_meshes_times_placements'], x['largest_stage_meshes']), reverse=True)
    candidates = [row for row in rows if row['largest_stage_meshes'] > 32 or
                  (row['source_mesh_nodes'] >= 48 and row['base_map_placements'] >= 10)]
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps({'schema_version': 1, 'models': rows}, ensure_ascii=False, indent=2) + '\n')
    text = '# Модели для переработки стадий разрушения\n\n'
    text += 'Источник: активные GLB и авторская base_office_map.json из репозитория. Это аудит геометрии, не замер FPS или числа физических тел. '
    text += 'Mesh-узел считается отдельно от mesh-ресурса и его material surfaces. Повторные ссылки на один ресурс считаются отдельными узлами; недостижимые узлы исключены. '
    text += 'Стадии определяются по тем же именам групп, которые использует environment_prop_geometry, и именам экспортированных сцен.\n\n'
    text += '**Важное ограничение:** environment_prop_breakup.spawn_stage уже ограничивает один вызов 32 фрагментами, стеклянные shards — 12. '
    text += 'Поэтому стадия из 93 мешей не означает 93 одновременно созданных физических тела. Однако её узлы и ресурсы заранее присутствуют в модели. '
    text += 'DamageReady — локальные сколы; её общий размер не равен числу сколов от одного попадания.\n\n'
    text += 'Таблица отсортирована по максимальному размеру стадии × числу прямых размещений GLB на базовой карте. '
    text += 'Размещения через structural .tscn не включены в эту колонку; 0 означает отсутствие прямых GLB-записей, а не отсутствие модели в игре. '
    text += 'Всего проверено %d активных моделей; %d выбраны: стадия больше 32 mesh-узлов либо модель с 48+ узлами и 10+ прямыми размещениями. Полные данные всех моделей — в соседнем JSON.\n\n' % (len(rows), len(candidates))
    text += '| Модель | Всего mesh-узлов | Стадии разрушения: mesh-узлы | Прямых размещений |\n|---|---:|---|---:|\n'
    for row in candidates:
        stages = ', '.join('%s: %d' % (name, data['meshes']) for name, data in row['stages'].items())
        text += '| `%s` | %d | %s | %d |\n' % (Path(row['path']).stem, row['source_mesh_nodes'], stages, row['base_map_placements'])
    text += '\n## Требования к переработке\n\n'
    text += '- В первую очередь обычные и конференционные стулья: уменьшить Fine/Medium, объединить мелкую фурнитуру, сохранить независимые ножки/спинку/сиденье.\n'
    text += '- Для крупных шкафов, стойки рецепции и диванов объединить соседние мелкие куски; отдельно оставлять только функциональные крупные элементы.\n'
    text += '- Начальный ориентир, не жёсткое правило: 12–24 физических фрагмента для стула, до 24–32 для крупной мебели. Более мелкую крошку представлять визуальным эффектом.\n'
    text += '- Сохранить UV, material slots, имена Intact и стадий, имена семейств деталей для prefix-matching, масштаб и pivot. Проверить переход каждого крупного фрагмента в следующую стадию.\n'
    text += '- Не объединять Intact со стадиями разрушения. Удалять неиспользуемые дубликаты; не подменять уменьшение mesh-узлов одним снижением числа треугольников.\n'
    args.report.write_text(text)
    print('Destruction audit: %d active models, %d rework candidates' % (len(rows), len(candidates)))
    for row in candidates[:12]:
        print(Path(row['path']).stem, row['source_mesh_nodes'], row['largest_stage_meshes'], row['base_map_placements'])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
