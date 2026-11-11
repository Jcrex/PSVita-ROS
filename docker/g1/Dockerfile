# Simulador del Unitree G1 para PSVita-ROS: MuJoCo + política de marcha OFICIAL de Unitree
# (unitreerobotics/unitree_rl_gym, deploy/pre_train/g1/motion.pt, BSD-3) + puente ROS 2 Jazzy.
# Se construye encima de la estación (docker/vita-ros.sh build) para heredar ROS 2 y la red del host.
FROM psvita-ros-station:jazzy

ARG UNITREE_RL_GYM_COMMIT=276801e46c5d433564f24658bac64f254b7d2d4b
RUN apt-get update && apt-get install -y --no-install-recommends git python3-pip && rm -rf /var/lib/apt/lists/*
# PyTorch solo CPU (la política es un MLP pequeño: ~0,1 ms por inferencia).
RUN pip3 install --break-system-packages --no-cache-dir \
        --index-url https://download.pytorch.org/whl/cpu torch \
 && pip3 install --break-system-packages --no-cache-dir mujoco pyyaml
RUN git clone https://github.com/unitreerobotics/unitree_rl_gym /opt/unitree_rl_gym \
 && cd /opt/unitree_rl_gym && git checkout ${UNITREE_RL_GYM_COMMIT} && rm -rf .git
COPY g1_sim.py casa.py casa.json /opt/g1/
ENV G1_RL_GYM=/opt/unitree_rl_gym
