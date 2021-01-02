from setuptools import setup, find_packages

name = 'project_template'

setup(
    name=name,
    description='Package ' + name,
    package_dir={'': 'src'},
    packages=find_packages(where='src'),
    include_package_data=True,
)
