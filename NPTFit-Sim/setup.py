from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

import numpy

extensions =[
    Extension("rej_samp",["rej_samp.pyx"]),
    Extension("make_map",["make_map.pyx"]),
]

setup (
    ext_modules = cythonize(extensions),
	include_dirs=[numpy.get_include()]
)
