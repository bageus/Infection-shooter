#!/usr/bin/env python3
"""Regression tests for lost scene membership and duplicate damage stages."""
import unittest
from build_group05_assets import stages


class StageTests(unittest.TestCase):
    def test_empty_scenes_are_repaired_from_authored_names(self):
        doc={'scene':1,'scenes':[{'name':'LargeParts'},{'name':'Scene','nodes':list(range(5))}],
             'nodes':[{'name':n} for n in ['Intact','Power_Off','Display_Lid','Display_Lid_fragment_1','Keyboard_Base']]}
        self.assertEqual(stages(doc),{'Intact':[0],'Power_Off':[1],'LargeParts':[2,4],'SmallFragments':[3]})

    def test_plain_prop_does_not_gain_damage(self):
        doc={'scenes':[{'name':'Assets','nodes':[0]}],'nodes':[{'name':'keyboard_body'}]}
        self.assertEqual(stages(doc),{'Intact':[0]})

    def test_duplicate_small_stage_is_removed(self):
        doc={'scenes':[{'name':'Intact','nodes':[0]},{'name':'LargeParts','nodes':[1,2]},
                       {'name':'SmallFragments','nodes':[1,2]}]}
        self.assertEqual(stages(doc),{'Intact':[0],'LargeParts':[1,2]})

    def test_real_small_fragments_and_power_off_are_retained(self):
        doc={'scenes':[{'name':'Intact','nodes':[0]},{'name':'LargeParts','nodes':[1]},
                       {'name':'SmallFragments','nodes':[2,3]},{'name':'Power_Off','nodes':[4]}]}
        self.assertEqual(stages(doc),{'Intact':[0],'LargeParts':[1],'SmallFragments':[2,3],'Power_Off':[4]})


if __name__=='__main__':unittest.main()
