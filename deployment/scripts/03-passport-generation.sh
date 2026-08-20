#!/bin/bash
set -e

ENVIRONMENT=${1:-local}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/deployment/envs/${ENVIRONMENT}.env"

SED_INPLACE="sed -i"
if [[ "$(uname)" == "Darwin" ]]; then
  SED_INPLACE="sed -i ''"
fi


if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Environment file not found: $ENV_FILE"
  exit 1
fi

# Load env vars
set -a
source "$ENV_FILE"
set +a

# Ensure namespace is set
if [ -z "$NAMESPACE" ]; then
  echo "❌ NAMESPACE is not defined in env file."
  exit 1
fi

# Re-fetch the new SERVER_POD name after the restart
until SERVER_POD=$(kubectl get pods -n "$NAMESPACE" -l app=server -o jsonpath='{.items[0].metadata.name}') && [ -n "$SERVER_POD" ]; do
  sleep 5
done

# Generate Laravel Passport Client Credentials (also as one-off)
if [ "$REACT_APP_CLIENT_ID" = "PLACE_HOLDER" ] || [ "$REACT_APP_CLIENT_SECRET" = "PLACE_HOLDER" ]; then
    echo "🏗️ Generating Laravel Passport Client Credentials..."

    echo "🔑 Ensuring Passport encryption keys are generated..."
    kubectl exec -n "$NAMESPACE" "$SERVER_POD" -- sh -c '
      cd /var/www/html &&
      chown -R www-data:www-data storage &&
      su -s /bin/sh www-data -c "php artisan config:clear && php artisan passport:keys --force" &&
      chown www-data:www-data storage/oauth-*.key &&
      chmod 600 storage/oauth-private.key &&
      chmod 644 storage/oauth-public.key'
    # Extract the keys from the pod
    PRIV_KEY=$(kubectl exec -n "$NAMESPACE" "$SERVER_POD" -- cat storage/oauth-private.key)
    PUB_KEY=$(kubectl exec -n "$NAMESPACE" "$SERVER_POD" -- cat storage/oauth-public.key)

    echo "💾 Persisting Passport keys to $ENV_FILE (replacing placeholders)..."

    # Flatten the multi-line keys into single lines with \n characters for sed
    # We use printf to avoid trailing newlines messing up the flatten logic
    PRIV_KEY_FLAT=$(printf "%s" "$PRIV_KEY" | sed ':a;N;$!ba;s/\n/\\n/g')
    PUB_KEY_FLAT=$(printf "%s" "$PUB_KEY" | sed ':a;N;$!ba;s/\n/\\n/g')

    # Replace placeholders (with or without quotes)
    $SED_INPLACE "s|PASSPORT_PRIVATE_KEY=.*|PASSPORT_PRIVATE_KEY=\"$PRIV_KEY_FLAT\"|" "$ENV_FILE"
    $SED_INPLACE "s|PASSPORT_PUBLIC_KEY=.*|PASSPORT_PUBLIC_KEY=\"$PUB_KEY_FLAT\"|" "$ENV_FILE"

    echo "🏗️ Extracting Client ID and Secret..."
    PASSPORT_OUTPUT=$(kubectl exec -n "$NAMESPACE" "$SERVER_POD" -- sh -c '
      cd /var/www/html &&
      su -s /bin/sh www-data -c "php artisan passport:client --password --name=\"CloudNotesClient\" --no-interaction --no-ansi"
    ')

    # Passport 13 prints "Client ID" and "Client Secret" in its formatted output.
    # Strip carriage returns so this works consistently in local shells and CI logs.
    CLIENT_ID=$(printf '%s\n' "$PASSPORT_OUTPUT" | tr -d '\r' | awk '/Client ID/{value=$NF} END{print value}')
    CLIENT_SECRET=$(printf '%s\n' "$PASSPORT_OUTPUT" | tr -d '\r' | awk '/Client Secret/{value=$NF} END{print value}')

    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        echo "❌ Failed to generate Passport credentials."
        echo "Passport did not return both a client ID and client secret."
        exit 1
    fi

    # Update the environment file on the host machine
    $SED_INPLACE "s|REACT_APP_CLIENT_ID=PLACE_HOLDER|REACT_APP_CLIENT_ID=$CLIENT_ID|" "$ENV_FILE"
    $SED_INPLACE "s|REACT_APP_CLIENT_SECRET=PLACE_HOLDER|REACT_APP_CLIENT_SECRET=$CLIENT_SECRET|" "$ENV_FILE"

    echo "🔐 Generated CLIENT_ID: $CLIENT_ID"
    echo "🔐 Generated CLIENT_SECRET: [redacted]"

    echo "🔐 Patching Kubernetes Secret with new Passport keys..."
    # Create a temporary secret locally to format the JSON payload safely
    PATCH_DATA=$(kubectl create secret generic temp-patch \
      --from-literal=PASSPORT_PRIVATE_KEY="$PRIV_KEY" \
      --from-literal=PASSPORT_PUBLIC_KEY="$PUB_KEY" \
      --dry-run=client -o jsonpath='{.data}')
      
    # Apply the patch to the actual secret
    kubectl patch secret cloudnotes-env -n "$NAMESPACE" -p="{\"data\":$PATCH_DATA}"
    
    echo "🔄 Restarting Server Pod to apply new keys..."
    kubectl rollout restart deployment server -n "$NAMESPACE"
    kubectl rollout status deployment server -n "$NAMESPACE" --timeout=300s
else
    echo "✅ REACT_APP_CLIENT_ID and REACT_APP_CLIENT_SECRET already set."
fi

echo "✅ ENV file updated with  Passport credentials."
