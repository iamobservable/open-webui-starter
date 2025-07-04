#!/bin/sh
set -e

echo "📡 Waiting for PostgreSQL to be ready at db:5432..."

until pg_isready -h postgres -p 5432 -U "$POSTGRES_USER" > /dev/null 2>&1; do
  echo "⏳ Still waiting for PostgreSQL..."
  sleep 2
done

echo "✅ PostgreSQL is ready."

# Validate if postgres exists
echo "🔍 Checking if database '$POSTGRES_DB' exists..."

if ! psql -h postgres -p 5432 -U "$POSTGRES_USER" -tc "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" | grep -q 1; then
  echo "📁 Creating database '$POSTGRES_DB'..."
  createdb -h postgres -p 5432 -U "$POSTGRES_USER" "$POSTGRES_DB"
else
  echo "✅ Database '$POSTGRES_DB' already exists."
fi

# Validate if pgvector extension enabled | enable
echo "🔍 Checking if 'vector' extension is enabled in '$POSTGRES_DB'..."

if ! psql -h postgres -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tc "SELECT 1 FROM pg_extension WHERE extname = 'vector';" | grep -q 1; then
  echo "➕ Enabling 'pgvector' extension in '$POSTGRES_DB'..."
  psql -h postgres -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS vector;"
  echo "✅ 'pgvector' extension enabled."
else
  echo "✅ 'pgvector' extension already enabled."
fi
