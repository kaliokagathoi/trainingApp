from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy

# Define the extension
extensions = [
    Extension(
        "options_ladder_fast",
        ["options_ladder_fast.pyx"],
        include_dirs=[numpy.get_include()],
        extra_compile_args=["-O3", "-ffast-math"],  # Optimization flags
        extra_link_args=["-O3"]
    )
]

setup(
    name="Options Ladder Fast",
    ext_modules=cythonize(extensions,
                         compiler_directives={
                             'boundscheck': False,
                             'wraparound': False,
                             'cdivision': True,
                             'language_level': 3
                         }),
    zip_safe=False,
)