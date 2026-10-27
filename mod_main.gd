extends Node

func _init():
	# 安装脚本扩展，直接覆盖原版升级界面的容器脚本
	var mod_dir = ModLoaderMod.get_unpacked_dir().plus_file("yuan-AutoLevelup")
	ModLoaderMod.install_script_extension(
		mod_dir.plus_file("extensions/upgrades_ui_player_container.gd")
	)
