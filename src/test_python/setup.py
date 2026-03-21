from setuptools import find_packages, setup
from Cython.Build import cythonize
import os

package_name = 'test_python'


ext_modules = []
try:
    _files = "test_python/*.py"
    ext_modules = cythonize(
        _files,
        compiler_directives={'language_level': '3'},
        force=True,
        quiet=True,
        exclude=["test_python/__init__.py"],
    )
except Exception as e:
    print(f"Cython warning: {e}")

setup(
    ext_modules=ext_modules,
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='jarunyawat',
    maintainer_email='jarunyawat.b@gmail.com',
    description='TODO: Package description',
    license='TODO: License declaration',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'talker = test_python.talker:main',
            'listener = test_python.listener:main',
            'webRTC_bridge = test_python.webcamRTC_transport:main',
        ],
    },
)
