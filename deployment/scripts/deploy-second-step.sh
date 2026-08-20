#!/bin/bash
set -e

ENVIRONMENT=${1:-local}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Starting second step of CloudNotes deployment ($ENVIRONMENT)..."

bash $SCRIPT_DIR/03-passport-generation.sh "$ENVIRONMENT"
bash $SCRIPT_DIR/04-build-client.sh "$ENVIRONMENT"
bash $SCRIPT_DIR/05-deploy-final.sh "$ENVIRONMENT"

echo "🎉 Deployment completed successfully!"
