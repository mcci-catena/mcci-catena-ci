# mcci-catena-ci

This repository is used to run the CI test for libraries and that can be seen under tab `Actions` in each repository.

This repository is also intended to be built on Linux (Ubuntu 18 or later) for development of CI test scripts. The build script might work with Ubuntu for Windows, but has not been tested.

## Run CI test in local machine

Follow below steps to run the CI test for a library (ex: arduio-lmic).

1. Open the Terminal in the path of `mcci-catena-ci`.

2. Use the command below, adding architecture (-a) and library name (-l) as option/argument.

    ```bash
    ./arduino-lmic-regress-wrap.sh -a samd -l ./libraries/arduino-lmic
    ```

## How to add CI-test support for a library

This section says how to add a CI test support to a new repository. Consider library `arduino-lorawan` as example for this section

1. Clone this repository:

    ```bash
    git clone <mcci-catena-ci_repository_path>
    ```

2. Clone the library in the same directory as `mcci-catena-ci` gets cloned:

    ```bash
    git clone <arduino-lorawan_repository_path>
    ```
3. Add the unique script for the library to have CI test. The script can be named as `<name-of-library>-regress-wrap.sh`. In this example, the script will be named as `arduino-lorawan-regress-wrap.sh`.

4. Add .github/Workflows to the library you are testing. Inside workflows the script has been added `(ci-arduinocli.yml)`. In the script add the path of your library and other dependencies.

5. To compile examples in github actions, Use the command in the script:

    ```bash
    bash mcci-catena-ci/arduino-lorawan-regress-wrap.sh -l libraries/${{env.MCCI_CI_LIBRARY}} -a ${{ matrix.arch }}
    ```
