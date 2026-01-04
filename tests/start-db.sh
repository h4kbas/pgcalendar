#!/bin/bash

# Script to start PostgreSQL test database for pgcalendar tests

set -e

PG_HOST=${PG_HOST:-localhost}
PG_PORT=${PG_PORT:-5433}
PG_USER=${PG_USER:-postgres}
PG_PASSWORD=${PG_PASSWORD:-postgres}
PG_DB=${PG_DB:-pgcalendar_test}
CONTAINER_NAME="pgcalendar-test"

echo "Starting PostgreSQL test database..."
echo "  Host: $PG_HOST"
echo "  Port: $PG_PORT"
echo "  Database: $PG_DB"
echo "  User: $PG_USER"
echo ""

# Check if container already exists
if docker ps -a | grep -q "$CONTAINER_NAME"; then
    echo "Container $CONTAINER_NAME already exists"
    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo "Container is already running"
    else
        echo "Starting existing container..."
        docker start "$CONTAINER_NAME"
    fi
else
    echo "Creating new container..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -e POSTGRES_USER="$PG_USER" \
        -e POSTGRES_PASSWORD="$PG_PASSWORD" \
        -e POSTGRES_DB="$PG_DB" \
        -p "$PG_PORT:5432" \
        postgres:15
fi

echo ""
echo "Waiting for PostgreSQL to be ready..."
sleep 3

# Wait for PostgreSQL to be ready
until docker exec "$CONTAINER_NAME" pg_isready -U "$PG_USER" -d "$PG_DB" > /dev/null 2>&1; do
    echo "Waiting for database..."
    sleep 2
done

echo "✓ PostgreSQL is ready!"
echo ""
echo "Installing pgcalendar extension..."

# Install extension
docker exec -i "$CONTAINER_NAME" psql -U "$PG_USER" -d "$PG_DB" -f /tmp/pgcalendar.sql 2>/dev/null || {
    # Copy SQL file to container if not already there
    docker cp ../pgcalendar.sql "$CONTAINER_NAME:/tmp/" > /dev/null 2>&1 || true
    docker exec -i "$CONTAINER_NAME" psql -U "$PG_USER" -d "$PG_DB" -f /tmp/pgcalendar.sql || {
        echo "⚠ Could not install extension automatically"
        echo "  You may need to install it manually:"
        echo "  docker exec -i $CONTAINER_NAME psql -U $PG_USER -d $PG_DB -f /path/to/pgcalendar.sql"
    }
}

echo "✓ Test database is ready!"
echo ""
echo "You can now run: npm test"
echo ""
echo "To stop the database:"
echo "  docker stop $CONTAINER_NAME"
echo ""
echo "To remove the database:"
echo "  docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"

