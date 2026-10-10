"""Regression coverage for wrap seams, negative UVs, zero-width UVs and tangent degeneracy."""
import unittest
import numpy as np
from build_group03_atlas import repeat_tri, tangents
from check_group03_atlas import areas

class AtlasTests(unittest.TestCase):
    def verify(self,uv):
        tri=np.zeros((3,12));tri[:,:3]=[[0,0,0],[1,0,0],[0,1,0]];tri[:,3:6]=[0,0,1];tri[:,6:8]=uv;tri[:,8:12]=1
        pieces=np.array(list(repeat_tri(tri,[.1,.2,.3,.4])))
        self.assertAlmostEqual(float(areas(pieces[:,:,:3]).sum()),.5,places=8)
        self.assertTrue((pieces[:,:,6:8]>=[.1-1e-8,.2-1e-8]).all())
        self.assertTrue((pieces[:,:,6:8]<=[.4+1e-8,.6+1e-8]).all())
        self.assertTrue(np.isfinite(tangents(pieces.reshape(-1,12))).all())
    def test_positive_repeats(self):self.verify([[0,0],[3.2,0],[0,2.5]])
    def test_negative_repeats(self):self.verify([[-2.2,-1.3],[1.2,-1.3],[-2.2,2.1]])
    def test_integer_line(self):self.verify([[1,0],[1,2],[1,4]])
    def test_integer_point(self):self.verify([[1,1],[1,1],[1,1]])
    def test_thin_boundary(self):self.verify([[1-2e-10,0],[1+2e-10,1],[1-2e-10,2]])

if __name__=='__main__':unittest.main()
