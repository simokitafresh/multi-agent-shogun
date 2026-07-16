#!/usr/bin/env bats

setup_file() {
    export SCRIPT="$BATS_TEST_DIRNAME/../../scripts/deploy_training.sh"
}

@test "deploy_training rejects help without touching operational YAML" {
    before="$(sha256sum "$BATS_TEST_DIRNAME/../../queue/shogun_to_karo.yaml")"
    run bash "$SCRIPT" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: ninja:target pairs required"* ]]
    after="$(sha256sum "$BATS_TEST_DIRNAME/../../queue/shogun_to_karo.yaml")"
    [ "$before" = "$after" ]
}

@test "deploy_training rejects a round without ninja target pairs" {
    run bash "$SCRIPT" R_fixture
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: ninja:target pairs required"* ]]
}
