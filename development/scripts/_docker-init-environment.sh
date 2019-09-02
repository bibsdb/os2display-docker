#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
bold=$(tput bold)
normal=$(tput sgr0)

cd /var/www/admin

# Set ownership and permissions if we don't have write-permission.
# We do this a bit more careful in order to support the situation where the
# codebase is mounted via nfs that will show a "wrong" ownership, still allow
# us to write, but will reject an attempt to change permission. In this 
# situation it is important to actually test whether we can write, and then
# skip the chown/chmod alltogether if we can.
function ensure_writable {
  TEST_PATH=$1
  if [[ ! -d "${TEST_PATH}" ]]; then
    mkdir -p "${TEST_PATH}"
  fi
  if ! gosu www-data test -w "${TEST_PATH}"; then
    chown -R www-data:www-data "${TEST_PATH}"
    chmod -R u+rw "${TEST_PATH}"
  fi
}

for TEST_PATH in app/cache app/log web/uploads web/uploads/media var; do
  ensure_writable "${TEST_PATH}"
done

# Release-builds has a populated vendor-folder, so no need to do an install.
if [[ ! -f /var/www/admin/.release ]]; then
  echo "Live source mount - doing a composer install"
  gosu www-data composer install
else
  echo "Release-build detected, skipping composer install"
fi

# Import upload backup.
UPLOADS_IMPORT_FILE=/opt/development/state-import/uploads.tar.gz
if [[ -f "${UPLOADS_IMPORT_FILE}" ]]; then
  echo "* Importing file state"
  rm -fr web/uploads/*
  tar -C web/uploads -zx --strip-components=1 -f "${UPLOADS_IMPORT_FILE}"
  ensure_writable web/uploads
fi

gosu www-data bin/console doctrine:migrations:migrate --no-interaction
gosu www-data bin/console os2display:core:templates:load
gosu www-data bin/console doctrine:query:sql "UPDATE ik_screen_templates SET enabled=1;"
gosu www-data bin/console doctrine:query:sql "UPDATE ik_slide_templates SET enabled=1;"
gosu www-data bin/console fos:user:create admin admin@example.com admin --super-admin || true

# TODO - only do this if the indexes has not already been enabled.
# Initialize the search index
JSON_RESULT=$(curl -s "http://search:3010/authenticate" -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data @<(cat <<EOF
{
   "apikey": "795359dd2c81fa41af67faa2f9adbd32"
  }
EOF
) 2>/dev/null)

TOKEN=$(echo $JSON_RESULT|php -r 'echo json_decode(fgets(STDIN))->token;')

curl -s "http://search:3010/api/e7df7cd2ca07f4f1ab415d457a6e1c13/activate" -H "Authorization: Bearer $TOKEN" 2>/dev/null


# Activate shared indexes
JSON_RESULT=$(curl -s "http://search:3010/authenticate" -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data @<(cat <<EOF
{
   "apikey": "88cfd4b277f3f8b6c7c15d7a84784067"
  }
EOF
) 2>/dev/null)

TOKEN=$(echo $JSON_RESULT|php -r 'echo json_decode(fgets(STDIN))->token;')

curl "http://search:3010/api/bibshare/activate" -H "Authorization: Bearer $TOKEN"
curl "http://search:3010/api/itkdevshare/activate" -H "Authorization: Bearer $TOKEN"

JSON_RESULT=$(curl -s "http://search:3010/authenticate" -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data @<(cat <<EOF
{
   "apikey": "795359dd2c81fa41af67faa2f9adbd32"
  }
EOF
) 2>/dev/null)

TOKEN=$(echo $JSON_RESULT|php -r 'echo json_decode(fgets(STDIN))->token;')

function initialise_type {
curl -s "http://search:3010/api" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data @<(cat <<EOF
{
      "index":"e7df7cd2ca07f4f1ab415d457a6e1c13",
      "type":"$1",
      "id":1,
      "data": {
        "name": "test",
        "user": 1,
        "created_at": 0
      }
}
EOF
)

curl -s "http://search:3010/api" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" -H "Content-Type:application/json" -X DELETE --data @<(cat <<EOF
{
      "index":"e7df7cd2ca07f4f1ab415d457a6e1c13",
      "type":"$1",
      "id":1
}
EOF
)
}

arr="Os2Display\\\\CoreBundle\\\\Entity\\\\Slide
Os2Display\\\\CoreBundle\\\\Entity\\\\Channel
Os2Display\\\\CoreBundle\\\\Entity\\\\Screen
Os2Display\\\\MediaBundle\\\\Entity\\\\Media"
# TODO only do this if the types have not already been initialized.
for TYPE in $arr
do
(
    initialise_type $TYPE
)
done

# In case the database contained data.
gosu www-data bin/console os2display:core:reindex
