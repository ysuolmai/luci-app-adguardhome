#!/bin/bash
PATH="/usr/sbin:/usr/bin:/sbin:/bin"
binpath=$(uci get AdGuardHome.AdGuardHome.binpath)
if [ -z "$binpath" ]; then
uci set AdGuardHome.AdGuardHome.binpath="/tmp/AdGuardHome/AdGuardHome"
binpath="/tmp/AdGuardHome/AdGuardHome"
fi
mkdir -p ${binpath%/*}
upxflag=$(uci get AdGuardHome.AdGuardHome.upxflag 2>/dev/null)
tagname=$(uci get AdGuardHome.AdGuardHome.tagname 2>/dev/null)

check_if_already_running(){
	running_tasks="$(ps |grep "AdGuardHome" |grep "update_core" |grep -v "grep" |awk '{print $1}' |wc -l)"
	[ "${running_tasks}" -gt "2" ] && echo -e "\nA task is already running." && EXIT 2
}

check_wgetcurl(){
	which curl && downloader="curl -L -k --retry 2 --connect-timeout 20 -o" && return
	which wget && downloader="wget --no-check-certificate -t 2 -T 20 -O" && return
	if ! apk info | grep -q wget; then
		apk update || (echo "Error updating apk" && EXIT 1)
		apk add wget || (echo "Error installing wget" && EXIT 1)
	fi
	if ! apk info | grep -q curl; then
		apk add curl || (echo "Error installing curl" && EXIT 1)
	fi
	check_wgetcurl
}

check_latest_version(){
	check_wgetcurl
	echo -e "Check for update..."
	if [ "$tagname" = "beta" ]; then
		latest_ver="$(echo `$downloader - https://api.github.com/repos/AdguardTeam/AdGuardHome/releases 2>/dev/null|grep -E '(tag_name|prerelease)'`|sed 's#"tag#\n"tag#g'|grep "true"|head -n1|cut -d '"' -f4 2>/dev/null)"
	else
		latest_ver="$($downloader - https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest 2>/dev/null|grep -E 'tag_name'|head -n1|cut -d '"' -f4 2>/dev/null)"
	fi
	if [ -z "${latest_ver}" ]; then
		echo -e "\nFailed to check latest version, please try again later." && EXIT 1
	fi
	now_ver="$($binpath --version 2>/dev/null | grep -m 1 -oE '[v]{0,1}[0-9]+[.][Bbeta0-9\.\-]+')"
	if [ "${latest_ver}"x != "${now_ver}"x ] || [ "$1" == "force" ]; then
		echo -e "Local version: ${now_ver}. Cloud version: ${latest_ver}."
		doupdate_core
	else
		echo -e "\nLocal version: ${now_ver}, cloud version: ${latest_ver}."
		echo -e "You're already using the latest version."
		if [ ! -z "$upxflag" ]; then
			filesize=$(ls -l $binpath | awk '{ print $5 }')
			if [ $filesize -gt 8000000 ]; then
				echo -e "start upx may take a long time"
				doupx
			fi
		fi
		EXIT 0
	fi
}

doupx(){
	Archt="$(uname -m)"
	case $Archt in
	"i386"|"i486"|"i586"|"i686")
		Arch="i386"
		;;
	"x86_64"|"amd64")
		Arch="amd64"
		;;
	"armv7l")
		Arch="arm"
		;;
	"aarch64")
		Arch="arm64"
		;;
	"mips"|"mipsel")
		Arch="mips"
		;;
	*)
		echo -e "Error: Architecture $Archt not supported." 
		EXIT 1
		;;
	esac
	upx_latest_ver="$($downloader - https://api.github.com/repos/upx/upx/releases/latest 2>/dev/null|grep -E 'tag_name'|grep -E '[0-9.]+' -o 2>/dev/null)"
	$downloader /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz "https://github.com/upx/upx/releases/download/v${upx_latest_ver}/upx-${upx_latest_ver}-${Arch}_linux.tar.xz" 2>&1
	if ! apk info | grep -q xz; then
		apk add xz || (echo "Error installing xz" && EXIT 1)
	fi
	mkdir -p /tmp/upx-${upx_latest_ver}-${Arch}_linux
	xz -d -c /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz | tar -x -C "/tmp" >/dev/null 2>&1
	if [ ! -e "/tmp/upx-${upx_latest_ver}-${Arch}_linux/upx" ]; then
		echo -e "Failed to download UPX." 
		EXIT 1
	fi
	rm /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz
}

doupdate_core(){
	echo -e "Updating core..."
	mkdir -p "/tmp/AdGuardHomeupdate"
	rm -rf /tmp/AdGuardHomeupdate/* >/dev/null 2>&1
	Arch="$(uname -m)"
	case $Arch in
	"i386"|"i486"|"i586"|"i686")
		Arch="386"
		;;
	"x86_64"|"amd64")
		Arch="amd64"
		;;
	"armv7l")
		Arch="armv7"
		;;
	"aarch64")
		Arch="arm64"
		;;
	*)
		echo -e "Error: Architecture $Arch not supported." 
		EXIT 1
		;;
	esac
	echo -e "Downloading latest version..."
	$downloader /tmp/AdGuardHomeupdate/AdGuardHome.tar.gz "https://github.com/AdguardTeam/AdGuardHome/releases/download/${latest_ver}/AdGuardHome_linux_${Arch}.tar.gz" 2>&1
	tar -zxf "/tmp/AdGuardHomeupdate/AdGuardHome.tar.gz" -C "/tmp/AdGuardHomeupdate/"
	downloadbin="/tmp/AdGuardHomeupdate/AdGuardHome/AdGuardHome"
	chmod 755 $downloadbin
	echo -e "Download complete. Starting update..."
	/etc/init.d/AdGuardHome stop nobackup
	rm -f "$binpath"
	mv -f "$downloadbin" "$binpath"
	/etc/init.d/AdGuardHome start
	rm -rf "/tmp/AdGuardHomeupdate" >/dev/null 2>&1
	echo -e "Core update successful. New version: ${latest_ver}."
	EXIT 0
}

EXIT(){
	rm /var/run/update_core 2>/dev/null
	[ "$1" != "0" ] && touch /var/run/update_core_error
	exit $1
}

main(){
	check_if_already_running
	check_latest_version $1
}
trap "EXIT 1" SIGTERM SIGINT
touch /var/run/update_core
rm /var/run/update_core_error 2>/dev/null
main $1
