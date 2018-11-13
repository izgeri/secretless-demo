# Secretless Demo

Visit [secretless.io](https://secretless.io) or the Secretless
[GitHub repo](https://github.com/cyberark/secretless-broker) for more details on
the background of Secretless.

In this demo, we deploy a demo app to Minikube that uses a PostgreSQL backend.
First we'll deploy it the traditional way, where the app must be set up to know
the credentials to connect to the DB. Then we'll deploy it with a Secretless Broker
sidecar, so that the app can run without credentials for the pg backend.

For more details on the demo, see the [about demo](#about-demo) section.

## Prerequisites

To run through this tutorial, you will need:

+ A running Kubernetes cluster (you can use [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) to run a cluster locally)
+ [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) configured to point to the cluster
+ [Docker CLI](https://docs.docker.com/install/)

Ensure you are using Minikube's built-in Docker daemon by running `eval $(minikube docker-env)` before starting.

## Steps to run the demo

### Steps for a privileged user
1. Deploy PostgreSQL backend
  ```
  pushd postgres
    # build the pg backend image
    docker build -t demo-backend .

    # create a namespace for the backend
    # deploy the backend to the namespace
    kubectl create namespace backend-ns
    kubectl create -n backend-ns -f manifest.yml
  popd
  ```
  The steps above deploy a PostgreSQL instance to Minikube in the `backend-ns` namespace configured with a `test_app` user.

  You can check that the backend is up by running
  ```
  kubectl logs -n backend-ns pg-0
  ```

2. Add PostgreSQL credentials to secret store
  ```
  # create app namespace
  kubectl create namespace demo-ns

  # add Kubernetes secrets
  kubectl create -n demo-ns \
    secret generic \
    demo-backend-creds \
    --from-literal=address="$(minikube ip):30001/postgres" \
    --from-literal=username="test_app" \
    --from-literal=password="SUPERSECRETPASSWORD"

  # add service account
  kubectl -n demo-ns create serviceaccount demo-sa

  # add role / rolebinding to entitle serviceaccount to access demo-backend-creds
  kubectl -n demo-ns create -f credential-entitlements.yml
  ```
  The steps above add Kubernetes secrets for the actual pg address, username, and password in the namespace of the application.

  You can check that the secrets have loaded properly by running
  ```
  kubectl get secret -n demo-ns demo-backend-creds -o yaml
  ```

3. Deploy Secretless Broker configuration as ConfigMap
  ```
  # deploy the secretless config to demo-ns
  kubectl -n demo-ns create configmap \
    demo-secretless-config \
    --from-file=secretless.yml
  ```

### Steps for a non-privileged user (e.g. developer)

#### Without Secretless
```
pushd traditional
  # deploy app without secretless
  kubectl -n demo-ns create -f manifest.yml
popd
```
This deploys `demo-traditional-application` without Secretless. The pet store app retrieves the Kubernetes secret values at deploy time (except for the DB address) and adds them to its environment - potentially leaving them exposed if the app accidentally logs its environment.

You can check the state of the traditional deployment by running
```
kc get pods -n demo-ns | grep demo-trad
```

#### With Secretless
```
pushd secretless
  # deploy app with secretless
  kubectl -n demo-ns create -f manifest.yml
popd
```
This deploys the `demo-application` with Secretless. Secretless loads the Kubernetes secrets values into its environment - but it's designed to ensure secret values _will never be logged_. The app is configured to connect with Secretless over localhost.

You can check the state of the Secretless deployment by running
```
kc get pods -n demo-ns | grep demo-app
```

## Testing the demo

The traditional app is available at `$(minikube ip):30002` and the Secretless app is at `$(minikube ip):30003`. We can examine our deployed apps via the command line or via the dashboard (if we run `minikube dashboard`).

### Basic test that we can add / view pets

- Traditional:
  ```
  # add a pet
  curl -i \
    -d '{"name": "New Mr. Snuggles"}' \
    -H "Content-Type: application/json" \
    $(minikube ip):30002/pet

  # get the pets
  curl -i $(minikube ip):30002/pets
  ```
- Secretless:
  ```
  # add a pet
  curl -i \
    -d '{"name": "Old Mr. Snuggles"}' \
    -H "Content-Type: application/json" \
    $(minikube ip):30003/pet

  # get the pets
  curl -i $(minikube ip):30003/pets
  ```

### Potentially exposed secrets in the traditional deployment
The `/vulnerable` route in the app dumps the app environment.

- Traditional:
  ```
  # look for DB env vars
  curl -i $(minikube ip):30002/vulnerable | tr ',' '\n' | grep DB
  ```
- Secretless:
  ```
  # look for DB env vars
  curl -i $(minikube ip):30003/vulnerable | tr ',' '\n' | grep DB
  ```

## About demo

The demo uses an existing [pet store demo application](https://github.com/conjurdemos/pet-store-demo) that exposes the following routes:

- `GET /pets` to list all the pets in inventory
- `POST /pet` to add a pet
  - Requires **Content-Type: application/json** header and body that includes **name** data
- `GET /vulnerable` Returns a dump of the app environment

There are additional routes that are also available, but these are the ones that we will use.

Pet data is stored in a PostgreSQL database, and the application may be configured to connect to the database by setting the `DB_URL`, `DB_USERNAME`, and `DB_PASSWORD` environment variables in the application's environment (following [12-factor principles](https://12factor.net/)).

When we deploy the application with the Secretless Broker to Minikube, we configure the application with the `DB_URL` environment variable pointing to the Secretless Broker _and no values set for the `DB_USERNAME` or `DB_PASSWORD` environment variables_.

In the demo we use Kubernetes Secrets as a backend; in practice, you would ideally use a fully featured vault to store the credentials in order to benefit from centralized access control, least privilege, audit, and compliance. Note in particular that the ServiceAccount method of privileging the app to access the secrets privileged the _pod_ and not a specific _container_, when we really want to grant access on a per-container basis. This can easily be achieved with a modern vault.
