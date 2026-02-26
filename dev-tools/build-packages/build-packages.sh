#!/bin/bash
set -euo pipefail

current_path="$( cd $(dirname $0) ; pwd -P )"
root_dir="${current_path}/../.."
app=""
base=""
revision="1"
security=""
version="$(jq -r '.version' ${root_dir}/VERSION.json)"
all_platforms="no"
deb="no"
rpm="no"
tar="no"
architecture="x64"
production="no"
commit_sha=$(git rev-parse --short HEAD)
output_dir="${current_path}/output"
tmp_dir="${current_path}/tmp"
config_dir="${root_dir}/config"
package_config_dir="${current_path}/config"
verbose="info"

trap clean INT
trap clean EXIT

log() {
    if [ "$verbose" = "info" ] || [ "$verbose" = "debug" ]; then
        echo "$@"
    fi
}

clean() {
    exit_code=$?
    echo
    echo "Cleaning temporary files..."
    echo
    # Clean the files
    rm -rf ${tmp_dir}
    rm -f ${current_path}/base/Docker/base-builder.sh
    rm -f ${current_path}/base/Docker/plugins
    rm -f ${current_path}/rpm/Docker/rpm-builder.sh
    rm -f ${current_path}/rpm/Docker/wazuh-dashboard.spec
    rm -f ${current_path}/deb/Docker/deb-builder.sh
    rm -rf ${current_path}/deb/Docker/debian
    trap '' EXIT
    exit ${exit_code}
}

ctrl_c() {
    clean 1
}

get_packages(){
  packages_list=(app base security)
  packages_names=("Wazuh plugins" "Wazuh Dashboard" "Security plugin")
  valid_url='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
  mkdir -p ${tmp_dir}
  cd ${tmp_dir}
  mkdir -p packages
  for i in "${!packages_list[@]}"; do
    package_var="${packages_list[$i]}"
    package_name="${packages_names[$i]}"
    package_url="${!package_var}"

    log
    log "Downloading ${package_name}"

    if [[ $package_url =~ $valid_url ]]; then
      if ! curl --output "packages/${package_var}.zip" --silent --fail "${package_url}"; then
        echo "The given URL or Path to the ${package_name} is not working: ${package_url}"
        clean 1
      fi
    else
      echo "The given URL or Path to the ${package_name} is not valid: ${package_url}"
      clean 1
    fi
    log "Done!"
    log
  done
  cd ..
}

build_tar() {
  log
  log "Building base package..."
  log
  mkdir -p ${output_dir}
  cp -r ${config_dir} ${tmp_dir}
  cd ./base
  dockerfile_path="${current_path}/base/Docker"
  container_name="dashboard-base-builder"
  cp ./base-builder.sh ${dockerfile_path}
  cp ./plugins ${dockerfile_path}
  cp ${root_dir}/VERSION.json ${dockerfile_path}
  docker build -t ${container_name} ${dockerfile_path} || return 1
  docker run -t --rm -v ${tmp_dir}/:/tmp:Z -v ${output_dir}/:/output:Z\
  ${container_name} ${version} ${revision} ${architecture} ${verbose} || return 1
  cd ..
}

build_rpm() {
  log "Building rpm package..."

  local workdir="${current_path}/rpm"
  local dockerfile_path="${workdir}/Docker"
  local container_name="dashboard-rpm-builder"

  cd "$workdir" || return 1

  cp -r "${package_config_dir}" "${tmp_dir}" || return 1
  cp ./rpm-builder.sh "${dockerfile_path}/" || return 1
  cp ./wazuh-dashboard.spec "${dockerfile_path}/" || return 1

  docker build -t "${container_name}" "${dockerfile_path}" || return 1

  docker run -t --rm \
    -v "${tmp_dir}/:/tmp:Z" \
    -v "${output_dir}/:/output:Z" \
    "${container_name}" \
    "${version}" "${revision}" "${architecture}" \
    "${commit_sha}" "${production}" "${verbose}" \
    || return 1

  cd "${current_path}" || return 1
}


build_deb() {
  log "Building deb package..."

  local workdir="${current_path}/deb"
  local dockerfile_path="${workdir}/Docker"
  local container_name="dashboard-deb-builder"

  cd "$workdir" || return 1

  cp -r "${package_config_dir}" "${tmp_dir}" || return 1
  cp ./deb-builder.sh "${dockerfile_path}/" || return 1
  cp -r ./debian "${dockerfile_path}/" || return 1

  docker build -t "${container_name}" "${dockerfile_path}" || return 1

  docker run -t --rm \
    -v "${tmp_dir}/:/tmp:Z" \
    -v "${output_dir}/:/output:Z" \
    "${container_name}" \
    "${version}" "${revision}" "${architecture}" \
    "${commit_sha}" "${production}" "${verbose}" \
    || return 1

  cd "${current_path}" || return 1
}



build(){
  log "Building package..."
  if [ "$all_platforms" == "yes" ]; then
    deb="yes"
    rpm="yes"
    tar="yes"
  fi
  get_packages
  build_tar

  if [ $deb == "yes" ]; then
    echo "Building deb package..."
    build_deb || return 1
  fi

  if [ $rpm == "yes" ]; then
    echo "Building rpm package..."
    build_rpm || return 1
  fi

  if [ "$tar" == "no" ]; then
    echo "Removing tar package..."
    rm -r $(find $output_dir -name "*.tar.gz")
  fi
}

help() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo "    -c, --commit-sha <sha>        Set the commit sha of this build."
    echo "    -a, --app <url/path>          Set the location of the .zip file containing the Wazuh plugin."
    echo "    -b, --base <url/path>         Set the location of the .tar.gz file containing the base wazuh-dashboard build."
    echo "    -s, --security <url/path>     Set the location of the .zip file containing the wazuh-security-dashboards-plugin."
    echo "        --all-platforms           Build for all platforms."
    echo "        --deb                     Build for deb."
    echo "        --rpm                     Build for rpm."
    echo "        --tar                     Build for tar."
    echo "        --production              [Optional] The naming of the package will be ready for production."
    echo "        --arm                     [Optional] Build for arm64 instead of x64."
    echo "        --debug                   [Optional] Debug mode."
    echo "        --silent                  [Optional] Silent mode. Will not work if --debug is set."
    echo "    -r, --revision <revision>     [Optional] Set the revision of this build. By default, it is set to 1."
    echo "    -h, --help                    Show this help."
    echo
    exit $1
}

# -----------------------------------------------------------------------------

main() {
    echo $0 "$@"

   while [ -n "${1-}" ]; do
  case "${1}" in
    "-c"|"--commit-sha")
      [ -n "${2-}" ] || help 1
      commit_sha="${2}"
      shift 2
      ;;
    "-a"|"--app")
      [ -n "${2-}" ] || help 1
      app="${2}"
      shift 2
      ;;
    "-b"|"--base")
      [ -n "${2-}" ] || help 1
      base="${2}"
      shift 2
      ;;
    "-s"|"--security")
      [ -n "${2-}" ] || help 1
      security="${2}"
      shift 2
      ;;
    "-r"|"--revision")
      [ -n "${2-}" ] || help 1
      revision="${2}"
      shift 2
      ;;
    "--production") production="yes"; shift ;;
    "--all-platforms") all_platforms="yes"; shift ;;
    "--deb") deb="yes"; shift ;;
    "--rpm") rpm="yes"; shift ;;
    "--tar") tar="yes"; shift ;;
    "--arm") architecture="arm64"; shift ;;
    "--silent") verbose="silent"; shift ;;
    "--debug") verbose="debug"; shift ;;
    "-h"|"--help") help 0 ;;
    *)
      echo "Unknown option: ${1}"
      help 1
      ;;
  esac
done

    if [ -z "$app" ] || [ -z "$base" ] || [ -z "$security" ]; then
        echo "You must specify the app, base and security."
        help 1
    fi

    if [ "$all_platforms" == "no" ] && [ "$deb" == "no" ] && [ "$rpm" == "no" ] && [ "$tar" == "no" ]; then
        echo "You must specify at least one package to build."
        help 1
    fi

    if [ "$verbose" = "debug" ]; then
      set -x
    fi

    build || exit 1

    exit 0
}

main "$@"
