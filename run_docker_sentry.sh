#!/bin/bash

POSTGRES_PASSWORD="secret"
POSTGRES_USER="sentry"

run_docker () {
  check_run () {
    container_id=`docker ps -a --filter name=${1} | grep -i ${1} | cut -d " " -f1`
    is_up=`docker ps -a --filter name=${1} | grep -i ${1} | grep -i up | cut -d " " -f1`
    echo "Container ${container_id} and ${is_up}"
    [ ! -z ${is_up} ] || ([ ! -z ${container_id} ] && docker start $1)
  }
  redis() {
    echo "Run docker redis.."
    check_run redis || docker run -d --name redis redis
  }
  postgres() {
    echo "Run docker postgress.."
    check_run postgres || docker run -d --name postgres \
    -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
    -e POSTGRES_USER=${POSTGRES_USER} postgres
  }

  sentry() {
    generate_key() {

      if [ ! -f .secret ]; then
        echo "Generating a new key.."
        docker run --rm sentry generate-secret-key > .secret
      fi
      cat .secret
    }

    # This is run for initial setup only
    #
    initial_setup () {
      echo "Intial setup of sentry..."
      SENTRY_SECRET_KEY=$1
      setup() {
        echo "Wait for 5 seconds for other container to up."
        sleep 5
        docker run -it --rm -e SENTRY_SECRET_KEY=$SENTRY_SECRET_KEY \
        --link postgres:postgres \
        --link redis:redis sentry upgrade
      }
      mark_done() {
        echo "SENTRY_SECRET_KEY=${SENTRY_SECRET_KEY}" > .setup
      }
      [ -f .setup ] || (setup &&  mark_done)
    }

    server() {
      echo "Run docker sentry..."
      SENTRY_SECRET_KEY=$1
      check_run sentry || docker run -d --name sentry -e SENTRY_SECRET_KEY=$SENTRY_SECRET_KEY \
      -p 8080:9000 \
      --link redis:redis \
      --link postgres:postgres sentry
    }
    celery() {
      SENTRY_SECRET_KEY=$1
      cron() {
        echo "Run docker cron celery..."
        check_run celery-cron || docker run -d --name  celery-cron \
        -e SENTRY_SECRET_KEY=${SENTRY_SECRET_KEY} \
        --link postgres:postgres --link redis:redis sentry run cron
      }

      worker() {
        echo "Run docker worker celery..."
        check_run celery-worker || docker run -d --name celery-worker \
        -e SENTRY_SECRET_KEY=${SENTRY_SECRET_KEY} \
        --link postgres:postgres --link redis:redis sentry run worker
      }

      cron && worker
    }

    SENTRY_SECRET_KEY=$(generate_key)

    echo "Obtain secret key: ${SENTRY_SECRET_KEY}"
    echo "Run initial setup."
    initial_setup ${SENTRY_SECRET_KEY} &&
    server ${SENTRY_SECRET_KEY} &&
    celery ${SENTRY_SECRET_KEY}
  }

  redis && postgres && sentry
}

echo "Run now.."

run_docker
