# shellcheck shell=bash

# This setup hook ensures CONFIG_MODULE_DECOMPRESS works, which enables
# in-kernel module decompression. This is based on the logic in
# <linux/kernel/module/decompress.c>.
checkModuleCompressionHook() {
  if ! grep --silent '^CONFIG_MODULE_DECOMPRESS=y$' @configfile@; then
    nixInfoLog "Skipping checkModuleCompressionHook, CONFIG_MODULE_DECOMPRESS is not enabled"
    return
  fi

  local compression_algo
  compression_algo=$(grep --extended-regexp '^CONFIG_MODULE_COMPRESS_(GZIP|XZ|ZSTD)=y$' @configfile@ | sed 's/CONFIG_MODULE_COMPRESS_\([A-Z]\+\)=y/\1/')

  if [[ -z "$compression_algo" ]]; then
    nixInfoLog "Skipping checkModuleCompressionHook, no module decompression algorithm is enabled"
    return
  fi

  local output
  local -a bad_module_files

  for output in $(getAllOutputNames); do
    case ${compression_algo,,} in
    # Nothing to check if gzip or zstd, the kernel does not use any special
    # compression parameters with those.
    gzip | zstd) ;;
    xz)
      local module_file
      while read -r module_file; do
        if ! xz --robot --list --verbose "$module_file" | grep --silent '^block.*\sCRC32$'; then
          bad_module_files+=("$module_file")
        fi
      done < <(find "${!output}/lib/modules/@modDirVersion@" -name '*.ko.xz' -type f)

      ;;
    *)
      nixWarnLog "Unknown kernel module compression algorithm \"${compression_algo,,}\", skipping check"
      ;;
    esac

    if ((${#bad_module_files[@]})); then
      local red='\033[0;31m'
      local no_color='\033[0m'
      printf "${red}Detected kernel modules that were not compressed with the following xz parameters \"--check=crc32\":${no_color}\n%s\n\n" "$(printf "  %s\n" "${bad_module_files[@]}")"
      exit 1
    fi
  done

  nixInfoLog "Finished checkModuleCompressionHook"
}

if [[ -z "${dontCheckModuleCompression-}" ]]; then
  nixInfoLog "Using checkModuleCompressionHook"
  postInstallHooks+=(checkModuleCompressionHook)
fi
