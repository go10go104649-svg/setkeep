"""Compatibility entry point: abs uses the shared upper-body renderer."""
import os
import runpy
from pathlib import Path

os.environ['SETKEEP_UPPER_CATEGORIES'] = 'abs'
runpy.run_path(str(Path(__file__).with_name('render_upper_body_categories.py')), run_name='__main__')
