import unittest
from audit_destruction_meshes import audit, stage_name


class DestructionMeshAuditTests(unittest.TestCase):
    def document(self):
        return {'nodes': [{'name': 'Intact', 'mesh': 0},
                          {'name': 'Fine', 'children': [2, 3]},
                          {'name': 'PieceA', 'mesh': 0},
                          {'name': 'PieceB', 'mesh': 0},
                          {'name': 'Unused', 'mesh': 0}],
                'scenes': [{'name': 'Assets', 'nodes': [0, 1]}],
                'meshes': [{'primitives': [{'attributes': {'POSITION': 0}, 'indices': 1}]}],
                'accessors': [{'count': 4}, {'count': 6}]}

    def test_counts_instances_not_unique_resources(self):
        row = audit(self.document(), 'model.glb', 10)
        self.assertEqual(row['source_mesh_nodes'], 3)
        self.assertEqual(row['stages']['Fine'], {'meshes': 2, 'triangles': 4})
        self.assertEqual(row['stage_meshes_times_placements'], 20)

    def test_exported_scene_stage(self):
        document = self.document()
        document['nodes'][1]['name'] = 'Container'
        document['scenes'] = [{'name': 'Intact', 'nodes': [0]},
                              {'name': 'SmallFragments', 'nodes': [1]}]
        row = audit(document, 'model.glb')
        self.assertEqual(row['stages']['SmallFragments']['meshes'], 2)
        self.assertEqual(row['source_mesh_nodes'], 3)

    def test_shared_nodes_are_not_double_counted_in_total(self):
        document = self.document()
        document['scenes'].append({'name': 'Fine', 'nodes': [1]})
        row = audit(document, 'model.glb')
        self.assertEqual(row['source_mesh_nodes'], 3)
        self.assertEqual(row['stages']['Fine']['meshes'], 2)

    def test_triangle_strip_and_non_triangle_primitive(self):
        document = self.document()
        primitive = document['meshes'][0]['primitives'][0]
        primitive['mode'] = 5
        self.assertEqual(audit(document, 'model.glb')['source_triangles'], 12)
        primitive['mode'] = 1
        self.assertEqual(audit(document, 'model.glb')['source_triangles'], 0)

    def test_group_names_match_runtime_convention(self):
        self.assertTrue(stage_name('Fine.001'))
        self.assertTrue(stage_name('LargeParts'))
        self.assertFalse(stage_name('FineDetail'))
        self.assertFalse(stage_name('Intact'))


if __name__ == '__main__':
    unittest.main()
