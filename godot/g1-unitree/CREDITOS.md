# Créditos y licencias — proyecto G1

| Material | Origen | Licencia |
|---|---|---|
| URDF y mallas del Unitree G1 (`g1_29dof_rev_1_0.urdf`, `meshes/*.STL`), diezmados en `robot/mallas_*` | [unitreerobotics/unitree_rl_gym](https://github.com/unitreerobotics/unitree_rl_gym) @ `276801e` (2025-07-25), `resources/robots/g1_description/` | BSD-3-Clause, Copyright (c) 2016-2023 HangZhou YuShu TECHNOLOGY CO.,LTD. ("Unitree Robotics") |
| Clips `anim/g1_marcha.json` | Grabados de la política oficial `deploy/pre_train/g1/motion.pt` del mismo repo, ejecutada en MuJoCo con `docker/g1/g1_sim.py` (bucle adaptado de `deploy/deploy_mujoco/deploy_mujoco.py`) | Datos derivados de material BSD-3 de Unitree Robotics |
| Casa (`casa/`) | Generada para este proyecto desde `docker/g1/casa.json` | la del repo |

Aviso BSD-3 de Unitree (se conserva al redistribuir): «Redistribution and use in source and binary forms, with or
without modification, are permitted provided that the following conditions are met: (1) Redistributions of source
code must retain the above copyright notice, this list of conditions and the following disclaimer. (2) Redistributions
in binary form must reproduce the above copyright notice […] in the documentation and/or other materials provided
with the distribution. (3) Neither the name of the copyright holder nor the names of its contributors may be used to
endorse or promote products derived from this software without specific prior written permission.» Texto completo:
`LICENSE` de unitree_rl_gym.
