[![Gem Version](https://badge.fury.io/rb/rom-distillery.svg)](https://badge.fury.io/rb/rom-distillery)

Requirements
============
* The 7z, zip, unzip programs


Usage
=====

~~~sh
# Get help
rhum --help

# Validat ROMs against DAT file
rhum -D ${datfile} validate ${rom_directory}

# Repack archive using 7z format
rhum repack -F 7z ${rom_directory}

# Generate checksum index
rhum index -i -p1 ${rom_directory}      # create .index in ${rom_directory}
rhum -m json index ${rom_directory}     # output index in JSON to stdout

# Save ROM header to the specified directory
rhum -d ${header_dir} header ${rom_directory}

# Remove unknown ROM
rhum -d ${save_dir} -D ${datfile} clean ${rom_directory}
~~~
