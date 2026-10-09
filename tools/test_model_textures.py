import json
import struct
import tempfile
import unittest
from pathlib import Path
from check_model_textures import audit


class ModelTexturesTests(unittest.TestCase):
    def check_document(self, document, binary=b'png!'):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[1]) as folder:
            path = Path(folder) / 'fixture.glb'
            data = json.dumps(document).encode()
            data += b' ' * (-len(data) % 4)
            path.write_bytes(struct.pack('<III', 0x46546C67, 2, 28 + len(data) + len(binary))
                             + struct.pack('<II', len(data), 0x4E4F534A) + data
                             + struct.pack('<II', len(binary), 0x004E4942) + binary)
            return audit(path)

    def document(self):
        return dict(images=[dict(bufferView=0)], bufferViews=[dict(byteLength=4)],
                    textures=[dict(source=0)], materials=[dict(pbrMetallicRoughness=
                    dict(baseColorTexture=dict(index=0)))], meshes=[dict(primitives=
                    [dict(material=0, attributes=dict(TEXCOORD_0=0))])])

    def test_textured_surface(self):
        result = self.check_document(self.document())
        self.assertEqual(result['errors'], [])
        self.assertEqual(result['textured'], 1)

    def test_missing_external_image(self):
        document = self.document()
        document['images'] = [dict(uri='deleted.png')]
        self.assertIn('image 0: missing external image', self.check_document(document)['errors'])

    def test_missing_uv(self):
        document = self.document()
        document['meshes'][0]['primitives'][0]['attributes'] = {}
        self.assertIn('baseColorTexture: missing TEXCOORD_0', self.check_document(document)['errors'])

    def test_truncated_embedded_image(self):
        document = self.document()
        document['bufferViews'][0]['byteLength'] = 20
        self.assertIn('image 0: invalid embedded payload', self.check_document(document)['errors'])

    def test_invalid_texture_index(self):
        document = self.document()
        document['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index'] = 3
        self.assertIn('baseColorTexture: invalid texture index', self.check_document(document)['errors'])


if __name__ == '__main__':
    unittest.main()
