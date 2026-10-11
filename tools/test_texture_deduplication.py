#!/usr/bin/env python3
"""Storage migration regressions: image bytes, geometry, indices and import profiles."""
import copy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import deduplicate_model_textures as dedup


class TextureDeduplicationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=dedup.ROOT.parent)
        self.root = Path(self.temporary.name)
        self.model = self.root / 'model.glb'
        self.image = self.root / 'shared texture.png'
        self.image.write_bytes(b'pixel-bytes')
        self.document = {
            'asset': {'version': '2.0'}, 'buffers': [{'byteLength': 24}],
            'bufferViews': [
                {'buffer': 0, 'byteOffset': 0, 'byteLength': 11},
                {'buffer': 0, 'byteOffset': 12, 'byteLength': 12, 'target': 34962},
            ],
            'images': [{'name': 'base-color', 'mimeType': 'image/png', 'bufferView': 0}],
            'textures': [{'source': 0, 'sampler': 0}], 'samplers': [{'wrapS': 33071}],
            'materials': [{'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}}}],
            'accessors': [{'bufferView': 1, 'componentType': 5126, 'count': 1, 'type': 'VEC3'}],
            'meshes': [{'primitives': [{'attributes': {'POSITION': 0}, 'material': 0}]}],
            'nodes': [{'mesh': 0}], 'scenes': [{'nodes': [0]}], 'scene': 0,
        }
        self.binary = self.image.read_bytes() + b'\0' + b'GEOMETRY1234'
        self.data = dedup.encode_glb(self.document, self.binary)

    def tearDown(self):
        self.temporary.cleanup()

    def test_externalization_preserves_every_semantic_field(self):
        rewritten = dedup.rewrite_glb(self.model, self.data, {0: self.image}, {})
        self.assertEqual(dedup.semantic_digest(self.model, self.data), dedup.semantic_digest(self.model, rewritten))
        document, binary = dedup.read_glb(rewritten)
        self.assertEqual(document['images'][0]['uri'], 'shared%20texture.png')
        self.assertNotIn('bufferView', document['images'][0])
        self.assertEqual(document['accessors'][0]['bufferView'], 0)
        self.assertEqual(dedup.view_bytes(document, binary, 0), b'GEOMETRY1234')
        for key in ('materials', 'textures', 'samplers', 'meshes', 'nodes', 'scenes'):
            self.assertEqual(document[key], self.document[key])

    def test_no_rewrite_is_byte_identical(self):
        self.assertEqual(self.data, dedup.rewrite_glb(self.model, self.data, {}, {}))

    def test_image_view_used_by_accessor_is_retained(self):
        document = copy.deepcopy(self.document)
        document['accessors'][0]['bufferView'] = 0
        data = dedup.encode_glb(document, self.binary)
        rewritten = dedup.rewrite_glb(self.model, data, {0: self.image}, {})
        after, binary = dedup.read_glb(rewritten)
        self.assertEqual(len(after['bufferViews']), 2)
        self.assertEqual(dedup.view_bytes(after, binary, after['accessors'][0]['bufferView']), self.image.read_bytes())

    def test_sparse_accessor_views_are_remapped(self):
        document = copy.deepcopy(self.document)
        document['accessors'][0]['sparse'] = {'count': 1, 'indices': {'bufferView': 1, 'componentType': 5121},
                                            'values': {'bufferView': 1}}
        data = dedup.encode_glb(document, self.binary)
        rewritten = dedup.rewrite_glb(self.model, data, {0: self.image}, {})
        after, _ = dedup.read_glb(rewritten)
        self.assertEqual(after['accessors'][0]['sparse']['indices']['bufferView'], 0)
        self.assertEqual(after['accessors'][0]['sparse']['values']['bufferView'], 0)
        self.assertEqual(dedup.semantic_digest(self.model, data), dedup.semantic_digest(self.model, rewritten))

    def test_existing_relative_uri_is_updated(self):
        document = copy.deepcopy(self.document)
        document['images'][0] = {'name': 'base-color', 'mimeType': 'image/png', 'uri': 'old.png'}
        old = self.root / 'old.png'
        old.write_bytes(self.image.read_bytes())
        data = dedup.encode_glb(document, self.binary)
        rewritten = dedup.rewrite_glb(self.model, data, {}, {old.resolve(): self.image})
        self.assertEqual(dedup.semantic_digest(self.model, data), dedup.semantic_digest(self.model, rewritten))

    def test_import_profiles_keep_real_processing_differences(self):
        a, b = self.root / 'a.png', self.root / 'b.png'
        a.write_bytes(b'pixels'); b.write_bytes(b'pixels')
        Path(str(a) + '.import').write_text('[params]\ncompress/mode=0\nroughness/mode=0\nroughness/src_normal="res://a.png"\n')
        Path(str(b) + '.import').write_text('[params]\ncompress/mode=0\nroughness/mode=0\nroughness/src_normal="res://b.png"\n')
        self.assertEqual(dedup.import_profile(a), dedup.import_profile(b))
        Path(str(b) + '.import').write_text('[params]\ncompress/mode=2\nroughness/mode=0\nroughness/src_normal=""\n')
        self.assertNotEqual(dedup.import_profile(a), dedup.import_profile(b))

    def test_plan_keeps_different_import_profiles(self):
        directory = self.root / 'models'
        directory.mkdir()
        a, b = directory / 'a.png', directory / 'b.png'
        a.write_bytes(b'pixels'); b.write_bytes(b'pixels')
        Path(str(a) + '.import').write_text('[params]\ncompress/mode=0\n')
        Path(str(b) + '.import').write_text('[params]\ncompress/mode=2\n')
        with patch.object(dedup, 'ROOT', self.root):
            aliases, _, _ = dedup.plan([a, b])
            self.assertFalse(aliases)
            Path(str(b) + '.import').write_text('[params]\ncompress/mode=0\n')
            aliases, _, _ = dedup.plan([a, b])
            self.assertEqual(aliases, {b.resolve(): a})

    def test_plan_excludes_ignored_authoring_sources(self):
        directory = self.root / 'models'
        directory.mkdir()
        a = directory / 'a.png'
        a.write_bytes(b'pixels')
        Path(str(a) + '.import').write_text('[params]\ncompress/mode=0\n')
        ignored = directory / 'authoring'
        ignored.mkdir()
        (ignored / '.gdignore').touch()
        b = ignored / 'b.png'
        b.write_bytes(b'pixels')
        Path(str(b) + '.import').write_text('[params]\ncompress/mode=0\n')
        with patch.object(dedup, 'ROOT', self.root):
            aliases, _, _ = dedup.plan([a, b])
            self.assertFalse(aliases)

    def test_external_geometry_buffer_preserves_semantics(self):
        document = copy.deepcopy(self.document)
        document['buffers'] = [{'byteLength': 12}, {'byteLength': 12, 'uri': 'geometry.bin'}]
        document['bufferViews'][1].update(buffer=1, byteOffset=0)
        (self.root / 'geometry.bin').write_bytes(b'GEOMETRY1234')
        data = dedup.encode_glb(document, self.binary[:12])
        self.assertEqual(dedup.semantic_digest(self.model, self.data), dedup.semantic_digest(self.model, data))
        self.assertEqual(data, dedup.rewrite_glb(self.model, data, {}, {}))

    def test_invalid_header_is_rejected(self):
        with self.assertRaises(ValueError):
            dedup.read_glb(b'INVALID!' + self.data[8:])


if __name__ == '__main__':
    unittest.main()
