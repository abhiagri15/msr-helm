#!/bin/sh
# ============================================================================
# custom_setenv.sh  (chart-managed — do NOT edit inside the container)
# ============================================================================
# Why this file exists:
#   The MSR container starts the JVM directly via bin/server.sh. It does NOT run
#   the Tanuki Java Service Wrapper, so the wrapper.java.additional.* directives
#   in custom_wrapper.conf are never parsed by the runtime on their own.
#
#   bin/server.sh DOES source this file (bin/custom_setenv.sh) after setenv.sh
#   and before launching java, and passes ${JAVA_CUSTOM_OPTS} to the JVM. So we
#   read custom_wrapper.conf here and translate every
#       wrapper.java.additional.<N>=<jvm-arg>
#   line into JAVA_CUSTOM_OPTS — giving the on-prem-style file real effect in
#   the pod.
#
# To add a JVM property in the future:
#   Add a line to files/<env>/configuration/custom_wrapper.conf, e.g.
#       wrapper.java.additional.407=-Dmy.prop=value
#       wrapper.java.additional.408=-XX:+SomeFlag
#   then redeploy. No template, script, or code changes are needed — every
#   wrapper.java.additional.* line is picked up automatically on pod restart.
#
# Scope: translates JVM system properties / -XX flags (wrapper.java.additional.*).
#   Native wrapper directives (wrapper.java.library.path.*, wrapper.ping.*, etc.)
#   are intentionally ignored — they are not JVM arguments.
# ============================================================================

_CW_FILE="/opt/softwareag/IntegrationServer/configuration/custom_wrapper.conf"

if [ -r "$_CW_FILE" ]; then
    _WRAPPER_OPTS=""
    while IFS= read -r _line; do
        # Strip CR — these files are frequently authored on Windows (CRLF).
        _line=$(printf '%s' "$_line" | tr -d '\r')
        case "$_line" in
            wrapper.java.additional.*=*)
                # Keep everything after the FIRST '=', so values that themselves
                # contain '=' or ':' (e.g. the XPathFactory mapping) survive intact.
                _arg=${_line#*=}
                if [ -n "$_arg" ]; then
                    _WRAPPER_OPTS="$_WRAPPER_OPTS $_arg"
                fi
                ;;
        esac
    done < "$_CW_FILE"

    if [ -n "$_WRAPPER_OPTS" ]; then
        JAVA_CUSTOM_OPTS="$JAVA_CUSTOM_OPTS$_WRAPPER_OPTS"
        export JAVA_CUSTOM_OPTS
        echo "[custom_setenv.sh] Applied custom_wrapper.conf JVM options:$_WRAPPER_OPTS"
    fi
fi
