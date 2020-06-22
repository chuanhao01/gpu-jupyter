#!/usr/bin/env bash
cd $(cd -P -- "$(dirname -- "$0")" && pwd -P)

# Set the path of the generated Dockerfile
export DOCKERFILE=".build/Dockerfile"
export STACKS_DIR=".build/docker-stacks"
# please test the build of the commit in https://github.com/jupyter/docker-stacks/commits/master in advance
export HEAD_COMMIT="04f7f60d34a674a2964d96a6cb97c57a7870a828"

while [[ "$#" -gt 0 ]]; do case $1 in
  -c|--commit) HEAD_COMMIT="$2"; shift;;
  --no-datascience-notebook) no_datascience_notebook=1;;
  --no-useful-packages) no_useful_packages=1;;
  -s|--slim) no_datascience_notebook=1 && no_useful_packages=1;;
  *) echo "Unknown parameter passed: $1" &&
    echo "Usage: $0 -c [sha-commit] # set the head commit of the docker-stacks submodule
    (https://github.com/jupyter/docker-stacks/commits/master). default: $HEAD_COMMIT."; exit 1;;
esac; shift; done


# Clone if docker-stacks doesn't exist, and set to the given commit or the default commit
ls $STACKS_DIR/README.md  > /dev/null 2>&1  || (echo "Docker-stacks was not found, cloning repository" \
 && git clone https://github.com/jupyter/docker-stacks.git $STACKS_DIR)
echo "Set docker-stacks to commit '$HEAD_COMMIT'."
if [[ "$HEAD_COMMIT" == "latest" ]]; then
  echo "WARNING, the latest commit of docker-stacks is used. This may result in version conflicts"
  cd $STACKS_DIR && git pull && cd -
else
  export GOT_HEAD="false"
  cd $STACKS_DIR && git pull && git reset --hard "$HEAD_COMMIT" > /dev/null 2>&1  && cd - && export GOT_HEAD="true"
  echo "$HEAD"
  if [[ "$GOT_HEAD" == "false" ]]; then
    echo "Error: The given sha-commit is invalid."
    echo "Usage: $0 -c [sha-commit] # set the head commit of the docker-stacks submodule (https://github.com/jupyter/docker-stacks/commits/master)."
    echo "Exiting"
    exit 2
  else
    echo "Set head to given commit."
  fi
fi

# Write the contents into the DOCKERFILE and start with the header
cat src/Dockerfile.header > $DOCKERFILE

echo "
############################################################################
#################### Dependency: jupyter/base-image ########################
############################################################################
" >> $DOCKERFILE
cat $STACKS_DIR/base-notebook/Dockerfile | grep -v BASE_CONTAINER >> $DOCKERFILE

# copy files that are used during the build:
cp $STACKS_DIR/base-notebook/jupyter_notebook_config.py .build/
cp $STACKS_DIR/base-notebook/fix-permissions .build/
cp $STACKS_DIR/base-notebook/start.sh .build/
cp $STACKS_DIR/base-notebook/start-notebook.sh .build/
cp $STACKS_DIR/base-notebook/start-singleuser.sh .build/
chmod 755 .build/*

echo "
############################################################################
################# Dependency: jupyter/minimal-notebook #####################
############################################################################
" >> $DOCKERFILE
cat $STACKS_DIR/minimal-notebook/Dockerfile | grep -v BASE_CONTAINER >> $DOCKERFILE

echo "
############################################################################
################# Dependency: jupyter/scipy-notebook #######################
############################################################################
" >> $DOCKERFILE
cat $STACKS_DIR/scipy-notebook/Dockerfile | grep -v BASE_CONTAINER >> $DOCKERFILE

# install Julia and R if not excluded or spare mode is used
if [[ "$no_datascience_notebook" != 1 ]]; then
  echo "
  ############################################################################
  ################ Dependency: jupyter/datascience-notebook ##################
  ############################################################################
  " >> $DOCKERFILE
  cat $STACKS_DIR/datascience-notebook/Dockerfile | grep -v BASE_CONTAINER >> $DOCKERFILE
else
  echo "Set 'no-datascience-notebook', not installing the datascience-notebook with Julia and R."
fi

# Note that the following step also installs the cudatoolkit, which is
# essential to access the GPU.
echo "
############################################################################
########################## Dependency: gpulibs #############################
############################################################################
" >> $DOCKERFILE
cat src/Dockerfile.gpulibs >> $DOCKERFILE

# install useful packages if not excluded or spare mode is used
if [[ "$no_useful_packages" != 1 ]]; then
  echo "
  ############################################################################
  ############################ Useful packages ###############################
  ############################################################################
  " >> $DOCKERFILE
  cat src/Dockerfile.usefulpackages >> $DOCKERFILE
else
  echo "Set 'no-useful-packages', not installing stuff within src/Dockerfile.usefulpackages."
fi

# Copy the demo notebooks and change permissions
cp -r extra/Getting_Started data
chmod -R 755 data/

# Copying config
cp src/jupyter_notebook_config.json .build/
echo >> $DOCKERFILE
echo "# Copy jupyter_notebook_config.json" >> $DOCKERFILE
echo "COPY jupyter_notebook_config.json /etc/jupyter/"  >> $DOCKERFILE

#cp $(find $(dirname $DOCKERFILE) -type f | grep -v $STACKS_DIR | grep -v .gitkeep) .

echo "GPU Dockerfile was generated successfully in file ${DOCKERFILE}."
echo "Run 'bash start-local.sh -p [PORT]' to start the GPU-based Juyterlab instance."
