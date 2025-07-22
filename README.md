Repository with models implemented using Discrete Event Specification (DEVS) formalism, through the CADMIUM tool, whose installation can be found in the user guide: https://cell-devs.sce.carleton.ca/index.php/cadmium/.

# Simulador DEVS StreamProcessing

## Requisitos de Sistema

El simulador de Stream Processing esta desarrollado en lenguaje C++ y los registros al termino de la ejecución son procesados con lenguaje Python. Por ende, para la ejecución de estas dos acciones generales, es necesario lo siguientes requerimientos:

### 1. Simulador de preprocesamiento en C++

#### Requisitos de software:
   • Sistema operativo: Linux (Ubuntu 20.04 o superior), macOS o Windows 10 con subsistema Cygwin o WSL.
   • Compilador: g++ versión 9.3 o superior, o clang++ equivalente.
   • Estándar requerido: Soporte para C++20.
   • Dependencias externas: bibliotecas como Boost, OpenMP y MPI.
   • Herramientas de construcción: GNU Make versión 3.8 o superior.
   • Sistema de control de versiones: Git para clonar el repositorio de Cadmium y del modelo de procesamiento de streams.

#### Requisitos de hardware recomendados:
   • Procesador multinúcleo (mínimo 4 núcleos).
   • Memoria RAM: al menos 4 GB.
   • Espacio en disco: 2 GB libres para almacenar registros de simulación.

### 2. Procesamiento y análisis de resultados en Python

#### Requisitos de software:
   • Python 3.13 o superior.
   • Bibliotecas necesarias:
   ◦ re (detección de expresiones regulares)
   ◦ collections (contenedores especializados)
   ◦ matplotlib (visualización)
   • Entorno virtual recomendado: venv o conda para gestión de dependencias.

#### Requisitos de hardware recomendados:
   • CPU estándar compatible (mismo entorno que el simulador).
   • Memoria RAM: mínimo 4 GB.
   • Espacio en disco: al menos 500 MB para archivos de métricas calculadas.

## Preparación de Ambiente

### 1. Windows con Cygwin
1. Descargar e instalar Cygwin desde [https://www.cygwin.com/].
2. Durante la instalación, asegurarse de incluir los paquetes necesarios de desarrollo (gcc-core, gcc-g++, make, cmake, libboost-devel,
openmpi, libopenmpi-devel, python3, python3-pip, git).
3. Finalizada la instalación, abrir la terminal de Cygwin e instalar paquete de Python:
```bash
$ pip3 install matplotlib
```
4. (Opcional) Crear y activar un entorno virtual en Python:
```bash
$ python3 -m venv venv
$ source venv/bin/activate
```

### 2. Windows mediante WSL
1. Activar el Subsistema de Windows para Linux (WSL):
   - Abrir PowerShell como administrador.
   - Ejecutar el comando: `wsl --install`
   - Reiniciar el equipo si es necesario.
2. Instalar una distribución de Linux (por ejemplo, Ubuntu 20.04) desde Microsoft Store.
3. Abrir la terminal de Ubuntu y actualizar los paquetes:
```bash
$ sudo apt update && sudo apt upgrade -y
```
4. Instalar herramientas necesarias para C++:
```bash
$ sudo apt install build-essential g++ cmake make -y
$ sudo apt install libboost-all-dev libopenmpi-dev openmpi-bin -y
```
5. Instalar Python:
```bash
$ sudo apt install python3 python3-pip python3-venv -y
```
6. Instalar Git:
```bash
$ sudo apt install git -y
```

### 3. Linux
1. Actualizar sistema:
```bash
$ sudo apt update && sudo apt upgrade -y
```
2. Instalar herramientas para C++:
```bash
$ sudo apt install build-essential g++ cmake make -y
$ sudo apt install libboost-all-dev libopenmpi-dev openmpi-bin -y
```
3. Instalar Python y Git:
```bash
$ sudo apt install python3 python3-pip python3-venv -y
$ sudo apt install git -y
```

### 4. MacOS
1. Instalar Homebrew:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
2. Instalar herramientas:
```bash
$ brew install gcc cmake make boost open-mpi python
```
3. Crear entorno virtual en Python:
```bash
$ python3 -m venv venv
$ source venv/bin/activate
$ pip3 install matplotlib
```
4. Instalar Git:
```bash
$ brew install git
```

---

Una vez listos los requisitos, se debe instalar la librería **Cadmium** para construir el modelo basado en DEVS. Instrucciones detalladas en su [documentación](https://cell-devs.sce.carleton.ca/index.php/cadmium/).

Luego, clonar este repositorio:
```bash
$ git clone https://github.com/NZAE000/DEVS-MODELS.git
```

## Documentación
### Estructura del Repositorio

- `atomics/`: se sitúan los ficheros headers que definen los componentes atómicos del modelo, tales como (e.g., `producer.hpp`, `node.hpp`).
- `bin/`: contiene todos los binarios ejecutables, por ejemplo el simulador `STREAM_PROCESSING`.
- `build/`: contiene todos lo binarios intermedios compilados, los cuales son enlazados para generar el binario ejecutable en `bin/`.
- `data_structures/`: abarca el código de las estructuras de datos que el desarrollador diseña para fines de segmentar el comportamiento del modelo en conceptos y responsabilidades que complementa a los modelos atómicos. Por ejemplo, están ubicados las estructuras que definen los tipos de mensajes que utilizan los puertos de comunicación entre componentes atómicos y acoplados, también las estructuras de los componentes de la arquitectura Flink y sus funciones.
- `distribution_test/`: incluye fuentes utilizados para probar distintas funciones de distribución aleatoria (normal, exponencial, etc) con el fin de conocer previamente valores aleatorios con ciertos argumentos elegidos para la simulación.
- `input_data/`: incluye los archivos .txt que yace la configuración de parámetros para la simulación (`arrival_rate.txt`, `hardware.hpp`, `hardware.txt`, `operator.txt` y `topology.txt`).
- `metrics/`: comprende la implementación para el cálculo de métricas y despliegue gráfico con Python.
- `simulation_result/`: sitúa archivos .txt que contiene el registro de mensajes y estados de los modelos atómicos de la pruebas unitarias, de integración y de sistema. El registro de sistema es el utilizado para la obtención de las métricas.
- `test/`: contiene código fuente principal para las pruebas unitarias, de integración y sistema. En los fuentes principales es donde se construye el modelo o partes del modelo de acuerdo al tipo de prueba, instanciando los componentes atómicos, puertos de modelos acoplados, el acoplamiento entre modelos, modelo superior, loggers y la llamada a ejecución de la simulación.
- `util/`: contiene código de utilidades necesarias, como funciones de distribución aleatoria.
- `makefile`: archivo que automatiza la compilación y construcción del simulador. Su propósito principal es gestionar dependencias y simplificar el proceso de compilación.
- `throughput_deploy.sh`: script que automatiza la ejecución de comandos para el despliegue de rendimiento.
- `utilization_deploy.sh`: script que automatiza lala ejecución de comandos para el despliegue de utilización.

## Manual de Usuario

Como requerimiento funcional, el simulador lee los archivos que están ubicados en el directorio `input_data` donde yacen los parámetros que el usuario define para la configuración del modelo. Luego, el usuario compila y ejecuta.

### Archivos de Configuración

- `arrival_rate.txt`: se definen los cambios de tasas de llagada en el instante que debe suceder para que el modelo productor simule los cambios de llegada de eventos al sistema. El instante y tasa sigue el formato `hr:min:sec:ms:us λ`. Nota: el primer instante de tiempo debe comenzar en cero `00:00:00:000:000 λ` y el ultimo valor de `λ` debe ser cero para indicar finalización de generación de eventos.
- `hardware.hpp`: asignar el número de máquinas y la cantidad de núcleos homogéneo del modelo clúster en la macro `N_NODES` y `N_CORES` respectivamente Nota: cada vez que se asigne una cantidad distinta, es necesario compilar, como se muestra mas adelante.
- `hardware.txt`: (en desarrollo) definición futura de hardware.
- `operator.txt`: definir las propiedades de los operadores que conforman la aplicación simulada. Cada propiedad debe seguir el formato `id réplica distribución args`.
- `topology.txt`: se define la topología de la aplicación a simular, comprendiendo los id de operadores definidos en el archivo `operator.txt`. Se debe seguir el formato `from to`.

### Compilación

Desde la raíz del modelo StreamProcessing:

```bash
$ make STREAM_PROCESSING N_NODES=3 N_CORES=2 -j
```

Para limpiar y recompilar:

```bash
$ make clean && make STREAM_PROCESSING N_NODES=3 N_CORES=2 -j
```

Si el usuario desea configurar otro número de nodos o núcleos, es necesario ejecutar el comando nuevamente. Una vez compilado, se procede a la ejecución del simulador.

### Ejecución

```bash
$ ./bin/STREAM_PROCESSING
```

Una vez ejecutado, habrán registros tanto de mensajes como de estados de los componentes atómicos en la carpeta `simulation_result/`. Aquellos registros pueden ser consumidos con el fin de generar y desplegar métricas de utilización tanto para nodos y operadores.

### Visualización de Métricas

Utilización:
```bash
$ bash utilization_deploy.sh 3 2
```

Throughput:
```bash
$ bash throughput_deploy.sh 3 2 30 1
```

> Donde `n_exec=30`(número de ejecuciones si es necesario una observación mas clara de la curva de rendimiento) y el último parámetro define si limpiar archivo anterior (1 = sí, 0 = no (acumular nuevos registros)).

---

> **Nota**: Para más información, consultar el documento completo del modelo o contactarse con el autor.

