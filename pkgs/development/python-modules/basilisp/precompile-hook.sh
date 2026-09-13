# shellcheck shell=bash

# Setup hook to compile a package's Basilisp namespaces at build time.
echo "Sourcing basilisp-precompile-hook.sh"

basilispPrecompilePhase() {
    echo "Executing basilispPrecompilePhase"

    # shellcheck disable=SC2154
    local sitePackages="$out/@pythonSitePackages@"
    if [[ ! -d "$sitePackages" ]]; then
        echo "No $sitePackages to compile Basilisp namespaces in"
        return 0
    fi

    # Basilisp compiles a namespace the first time it is imported and caches the
    # bytecode in `__pycache__` next to the source, which it cannot do once the
    # source is in the store. The cache is keyed on the source mtime, so
    # normalize it to the value the store will give it before compiling.
    find "$sitePackages" \( -name '*.lpy' -o -name '*.cljc' \) -exec touch -d @1 {} +

    if [[ -z "${basilispNamespaces[*]-}" ]]; then
        # shellcheck disable=SC2207
        basilispNamespaces=($(
            find "$sitePackages" \( -name '*.lpy' -o -name '*.cljc' \) -printf '%P\n' \
                | sed -e 's|\.lpy$||' -e 's|\.cljc$||' -e 's|/|.|g' -e 's|\.__init__$||' \
                | sort
        ))
    fi

    if [[ -z "${basilispNamespaces[*]-}" ]]; then
        echo "No Basilisp namespaces found in $sitePackages"
        return 0
    fi

    echo "Compiling the following Basilisp namespaces: ${basilispNamespaces[*]}"
    # Compile from within the installed tree: the interpreter puts the working
    # directory first on `sys.path`, where a leftover copy in the build tree
    # would shadow what the package actually installed.
    # Basilisp namespace names are munged to Python identifiers, which must not
    # contain spaces, so the expansion below is safe to split.
    # shellcheck disable=SC2048,SC2086
    (
        cd "$sitePackages" || return 1
        PYTHONPATH="$sitePackages${PYTHONPATH:+:$PYTHONPATH}" \
            @pythonInterpreter@ @precompileScript@ "$sitePackages" ${basilispNamespaces[*]}
    )
}

if [[ -z "${dontUseBasilispPrecompile-}" ]]; then
    echo "Using basilispPrecompilePhase"
    appendToVar preDistPhases basilispPrecompilePhase
fi
