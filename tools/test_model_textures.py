import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from check_model_textures import audit, validate_png


class ModelTexturesTests(unittest.TestCase):
    def png(self, compressed=None):
        def chunk(kind, payload):
            return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
        image = zlib.compress(b'\x00\x80\x80\xff') if compressed is None else compressed
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', image) + chunk(b'IEND', b''))

    def test_png_integrity(self):
        validate_png(self.png())
        for bad in (self.png()[:-14], self.png()[:-12]):
            with self.assertRaises(ValueError):
                validate_png(bad)
        with self.assertRaisesRegex(ValueError, 'Truncated PNG image stream'):
            validate_png(self.png(zlib.compress(b'\x00\x80\x80\xff')[:-3]))

    def test_embedded_corrupt_png(self):
        document = self.document()
        broken = self.png()[:-14]
        document['bufferViews'][0]['byteLength'] = len(broken)
        document['images'][0]['mimeType'] = 'image/png'
        self.assertTrue(any('PNG' in error for error in self.check_document(document, broken)['errors']))

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
