#!/bin/bash

ENV_NAME=".venv"

echo "Creating virtual environment..."

python3 -m venv $ENV_NAME

echo "Activating environment..."

source $ENV_NAME/bin/activate

echo "Installing dependencies..."

pip install --upgrade pip

pip install -r py-requirements.txt

echo
echo "Environment ready."
echo
echo "Activate later with:"
echo "source $ENV_NAME/bin/activate"
echo
echo "Deactivate with:"
echo "deactivate"
