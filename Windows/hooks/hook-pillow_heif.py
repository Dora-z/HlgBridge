from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs, collect_submodules, collect_delvewheel_libs_directory

datas = collect_data_files("pillow_heif")
binaries = collect_dynamic_libs("pillow_heif")
datas, binaries = collect_delvewheel_libs_directory("pillow_heif", datas=datas, binaries=binaries)
hiddenimports = collect_submodules("pillow_heif") + ["_pillow_heif"]
