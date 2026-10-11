# Optional overrides for testing with an extracted zsh distribution.
# CI's complete system installation needs neither variable.
if [[ -n "${SHM_TEST_ZSH_MODULE_PATH:-}" ]]; then
    module_path=("$SHM_TEST_ZSH_MODULE_PATH" $module_path)
fi
if [[ -n "${SHM_TEST_ZSH_FUNCTIONS:-}" ]]; then
    fpath=("$SHM_TEST_ZSH_FUNCTIONS" "$SHM_TEST_ZSH_FUNCTIONS"/*(N/)
        "$SHM_TEST_ZSH_FUNCTIONS"/Completion/*(N/))
fi
