#!/bin/bash
### $1:dis dev hoc 会覆盖config文件的EnvironmentString字段

# 配置plist文件的路径
config_plist_path=$(cd `dirname $0`; pwd)/config.plist
# exportOptionsPlist文件位置
export_options_plist_path=$(cd `dirname $0`; pwd)/exportOptionsPlist

# 读取环境参数 dev hoc dis
production_environment=$(/usr/libexec/PlistBuddy -c "print EnvironmentString" ${config_plist_path})

if [[ -n "$1" ]]; then
	production_environment=$1
fi
 
if [[ "$production_environment" != "dev" && "$production_environment" != "hoc" && "$production_environment" != "dis" ]]; then
	echo "================ 请输入正确的 EnvironmentString (Option: dev hoc dis) ============="
	exit 1
fi

# 设置GCC_PREPROCESSOR_DEFINITIONS
if [ $production_environment == "dev" ]; then
	GCC_PREPROCESSOR_DEFINITIONS="COCOAPODS=1 SD_WEBP=1"
else
	GCC_PREPROCESSOR_DEFINITIONS="PET_PRODUCTION_ENVIRONMENT=1 COCOAPODS=1 SD_WEBP=1"
fi

# 读取build number
if [ $production_environment == "dev" ]; then
	build_number_key=BuildNumberDev
else
	build_number_key=BuildNumberHoc
fi
build_number=$(/usr/libexec/PlistBuddy -c "print ${build_number_key}" ${config_plist_path})

# 检测build number
if [[ $build_number =~ ^[0-9]{10}$ && ${build_number:0:8} == $(date +%Y%m%d) ]]; then
	build_number=$[ $build_number + 1 ]
else
	build_number=$(date +%Y%m%d)01
fi

echo "================ build_number:${build_number} production_environment:${production_environment} ============="

# 工程环境路径 
workspace_path=$(/usr/libexec/PlistBuddy -c "print WorkspacePath" ${config_plist_path})

if [ ! -d ${workspace_path} ]; then
	echo "================ 请输入正确的 WorkspacePath:${workspace_path} ============="
	exit 1
fi

# 进入要工作的文件夹 
cd ${workspace_path}

# 去svn上拉取最新的代码 
#svn update 版本有bug


# info.plist文件的位置 
project_name=$(/usr/libexec/PlistBuddy -c "print ProjectName" ${config_plist_path})
if test ! -n "$project_name"
then
	echo "================ 请输入 ProjectName ============="
	exit 1
fi
info_plist_path=${workspace_path}/${project_name}/Info.plist

# 修改build号
if [ $production_environment == "dev" ]; then
	plist_build_number=${build_number}"test"
else
	plist_build_number=${build_number}
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $plist_build_number" ${info_plist_path}

# 获取版本号
build_version=$(/usr/libexec/PlistBuddy -c "print CFBundleShortVersionString" ${info_plist_path})

echo "================ 版本信息：build_version:${build_version} plist_build_number:${plist_build_number} ============="


# 工程项目名称 
workspace_name=$(/usr/libexec/PlistBuddy -c "print WorkspaceName" ${config_plist_path})
if test ! -n "$workspace_name"
then
	echo "================ 请输入 WorkspaceName ============="
	exit 1
fi

# scheme名称 
scheme_name=$(/usr/libexec/PlistBuddy -c "print SchemeName" ${config_plist_path})
if test ! -n "$scheme_name"
then
	echo "================ 请输入 SchemeName ============="
	exit 1
fi

# 指定打包输出文件路径
archive_base_path=$(/usr/libexec/PlistBuddy -c "print OutputPath" ${config_plist_path})/${workspace_name}
if test ! -n "$archive_base_path"
then
	echo "================ 请输入 OutputPath ============="
	exit 1
fi

# 路径环境KEY (dev,hoc,dis)
archive_environment_key=$production_environment

# 归档路径
archive_name=${workspace_name}_${archive_environment_key}_${build_version}_${build_number}.xcarchive
archive_path=${archive_base_path}/archive/archive_${archive_environment_key}/${archive_name}


# 清除
echo "================ Clean project ================"
xcodebuild clean 

# 开始归档
echo "================ 开始归档 ================"
xcodebuild archive -workspace ${workspace_name}.xcworkspace GCC_PREPROCESSOR_DEFINITIONS="${GCC_PREPROCESSOR_DEFINITIONS}" -scheme ${scheme_name} -configuration Release -archivePath ${archive_path}

#检查文件是否存在
if [ -e ${archive_path} ]; then
	echo "=== 归档成功: ${archive_path} ==="
else
	echo "=== 归档失败 ==="
	exit 1
fi


#打包默认生成的文件名 和临时路径
ipa_temp_name=${scheme_name}.ipa
ipa_temp_path=${archive_base_path}/ipa/ipa_temp

# 开始打包
# 指定ipa路径
ipa_name=${workspace_name}_${archive_environment_key}_${build_version}_${build_number}.ipa 
ipa_base_path=${archive_base_path}/ipa/ipa_${archive_environment_key}
ipa_path=${ipa_base_path}/${ipa_name}

if [ $production_environment == "dev" ]; then
	echo "================ 开始生成dev包 ================"
	options_plist_key=ProvisioningProfileDev
elif [ $production_environment == "hoc" ]; then
	echo "================ 开始生成hoc包 ================"
	options_plist_key=ProvisioningProfileHoc
elif [ $production_environment == "dis" ]; then
#生成dis包的时候需要同时生成hoc包并上传svn供测试使用
	echo "================ 开始生成dis包 ================"
	echo "================ 开始生成hoc包 ================"
	ipa_name=${workspace_name}_hoc_${build_version}_${build_number}.ipa 
	ipa_base_path=${archive_base_path}/ipa/ipa_hoc
	ipa_path=${ipa_base_path}/${ipa_name}

	#path2 才是真正的dis包
	ipa_name2=${workspace_name}_dis_${build_version}_${build_number}.ipa 
	ipa_base_path2=${archive_base_path}/ipa/ipa_dis
	ipa_path2=${ipa_base_path2}/${ipa_name2}

	options_plist_key=ProvisioningProfileHoc
	options_plist_key2=ProvisioningProfileDis
fi

#创建ipa文件夹
mkdir -p ${ipa_base_path}

options_plist_name=$(/usr/libexec/PlistBuddy -c "print ${options_plist_key}" ${config_plist_path})
xcodebuild -exportArchive -archivePath ${archive_path} -exportPath ${ipa_temp_path} -exportOptionsPlist ${export_options_plist_path}/${options_plist_name}
mv ${ipa_temp_path}/${ipa_temp_name} ${ipa_path}


#如果需要 创建dis包
if [ $production_environment == "dis" ]; then
	mkdir -p ${ipa_base_path2}

	options_plist_name2=$(/usr/libexec/PlistBuddy -c "print ${options_plist_key2}" ${config_plist_path})
    xcodebuild -exportArchive -archivePath ${archive_path} -exportPath ${ipa_temp_path} -exportOptionsPlist ${export_options_plist_path}/${options_plist_name2}
    mv ${ipa_temp_path}/${ipa_temp_name} ${ipa_path2}
fi

#检查文件是否存在
if [ -f ${ipa_path} ]; then
	echo "=== 打包成功: ${ipa_path} ==="
	#更新build Number
	/usr/libexec/PlistBuddy -c "Set :$build_number_key $build_number" ${config_plist_path}

	#上传到svn服务器
	if [ $production_environment == "dev" ]; then
		svn_ipa_base_path_key=SVNPathDev
	else
		svn_ipa_base_path_key=SVNPathHoc
	fi
	svn_ipa_base_path=$(/usr/libexec/PlistBuddy -c "print $svn_ipa_base_path_key" ${config_plist_path})
	svn_ipa_path=${svn_ipa_base_path}/${build_version}/${ipa_name}

	echo "=== 上传到svn服务器 ==="
	svn import ${ipa_path} ${svn_ipa_path} -m "${ipa_name}"
	#上传到fir服务器
	#fir publish ${ipa_dev_path} -c "测试服 Pet_dev_${ipa_name}"
else
	echo "=== 打包失败 ==="
	exit 1
fi





