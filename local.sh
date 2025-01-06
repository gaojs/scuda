#!/bin/bash

libscuda_path="$(pwd)/libscuda.so"
client_path="$(pwd)/client.cpp $(pwd)/codegen/gen_client.cpp $(pwd)/codegen/manual_client.cpp"
server_path="$(pwd)/server.cu $(pwd)/codegen/gen_server.cpp $(pwd)/codegen/manual_server.cpp"
server_out_path="$(pwd)/server.so"

build() {
  echo "building client..."

  if [[ "$(uname)" == "Linux" ]]; then
    nvcc --cudart=shared -Xcompiler -fPIC -I/usr/local/cuda/include -o "$(pwd)/client.o" -c "$(pwd)/client.cpp"
    nvcc --cudart=shared -Xcompiler -fPIC -I/usr/local/cuda/include -o "$(pwd)/codegen/gen_client.o" -c "$(pwd)/codegen/gen_client.cpp"
    nvcc --cudart=shared -Xcompiler -fPIC -I/usr/local/cuda/include -o "$(pwd)/codegen/manual_client.o" -c "$(pwd)/codegen/manual_client.cpp"

    echo "linking client files..."

    g++ -shared -fPIC -o libscuda.so "$(pwd)/client.o" "$(pwd)/codegen/gen_client.o" "$(pwd)/codegen/manual_client.o" \
        -L/usr/local/cuda/lib64 -lcudart -lcuda -lstdc++

  else
    echo "No compiler options set for os $(uname)"
  fi

  echo "building vector file for test..."

  if [ ! -f "$libscuda_path" ]; then
    echo "libscuda.so not found. build may have failed."
    exit 1
  fi
}

server() {
  echo "building server..." 

  if [[ "$(uname)" == "Linux" ]]; then
    nvcc --compiler-options -g,-Wno-deprecated-declarations -o $server_out_path $server_path -lnvidia-ml -lcuda -lcublas -lcudnn --cudart=shared
  else
    echo "No compiler options set for os "$(uname)""
  fi

  echo "starting server... $server_out_path"

  "$server_out_path"
}

ansi_format() {
  case "$1" in
  "pass")
    echo -e "\e[32m   ✓ $2\e[0m"
    ;;
  "fail")
    echo -e "\e[31m    ✗ $2\e[0m"
    ;;
  "emph")
    echo -e "\e[1m$2\e[0m"
    ;;
  *)
    echo "$2"
    ;;
  esac
}

#---- lists tests here ----#
test_cuda_available() {
  pass_message=$1
  fail_message=$2

  output=$(LD_PRELOAD="$libscuda_path" python3 -c "import torch; print(torch.cuda.is_available())" | tail -n 1)

  if [[ "$output" == "True" ]]; then
    ansi_format "pass" "$pass_message"
  else
    ansi_format "fail" "CUDA is not available. Expected True but got [$output]."
    return 1
  fi
}

test_tensor_to_cuda() {
  output=$(LD_PRELOAD="$libscuda_path" python3 -c "
import torch
print('Creating a tensor...')
tensor = torch.zeros(10, 10)
print('Moving tensor to CUDA...')
tensor = tensor.to('cuda:0')
print('Tensor successfully moved to CUDA')
" | tail -n 1)

  if [[ "$output" == "Tensor successfully moved to CUDA" ]]; then
    ansi_format "pass" "$pass_message"
  else
    ansi_format "fail" "Tensor failed. Got [$output]."
    return 1
  fi
}

test_tensor_to_cuda_to_cpu() {
  output=$(LD_PRELOAD="$libscuda_path" python3 -c "
import torch
print('Creating a tensor...')
tensor = torch.full((10, 10), 5)
print('Tensor created on CPU:')
print(tensor)

print('Moving tensor to CUDA...')
tensor_cuda = tensor.to('cuda:0')
print('Tensor successfully moved to CUDA')

print('Moving tensor back to CPU...')
tensor_cpu = tensor_cuda.to('cpu')
print('Tensor successfully moved back to CPU:')
" | tail -n 1)

  if [[ "$output" == "Tensor successfully moved back to CPU:" ]]; then
    ansi_format "pass" "$pass_message"
  else
    ansi_format "fail" "Tensor failed. Got [$output]."
    return 1
  fi
}

test_vector_add() {
  output=$(LD_PRELOAD="$libscuda_path" ./vector.o | tail -n 1)

  if [[ "$output" == "PASSED" ]]; then
    ansi_format "pass" "$pass_message"
  else
    ansi_format "fail" "vector_add failed. Got [$output]."
    return 1
  fi
}

test_cudnn() {
  output=$(LD_PRELOAD="$libscuda_path" ./cudnn.o | tail -n 1)

  if [[ "$output" == "New array: 0.5 0.731059 0.880797 0.952574 0.982014 0.993307 0.997527 0.999089 0.999665 0.999877 " ]]; then
    ansi_format "pass" "$pass_message"
  else
    ansi_format "fail" "test_cudnn failed. Got [$output]."
    return 1
  fi
}

test_cublas_batched() {
  output=$(LD_PRELOAD="$libscuda_path" ./cublas_batched.o | tail -n 5)

  expected_output=$'=====\nC[1]\n111.00 122.00\n151.00 166.00\n====='

  # trim ugly output from the file
  output=$(echo "$output" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  expected_output=$(echo "$expected_output" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ "$output" == "$expected_output" ]]; then
    ansi_format "pass" "$pass_message"
  else
    ansi_format "fail" "test_cublas_batched failed. Got [$output]."
    return 1
  fi
}

test_unified_mem() {
  output=$(LD_PRELOAD="$libscuda_path" ./unified_pointer.o | tail -n 1)

  if [[ "$output" == "Max error: 0" ]]; then
    ansi_format "pass" "$pass_message"
  else
    ansi_format "fail" "vector_add failed. Got [$output]."
    return 1
  fi
}

#---- declare test cases ----#
declare -A test_cuda_avail=(
  ["function"]="test_cuda_available"
  ["pass"]="CUDA is available."
)

declare -A test_tensor_to_cuda=(
  ["function"]="test_tensor_to_cuda"
  ["pass"]="Tensor moved to CUDA successfully."
)

declare -A test_tensor_to_cuda_to_cpu=(
  ["function"]="test_tensor_to_cuda_to_cpu"
  ["pass"]="Tensor successfully moved to CUDA and back to CPU."
)

declare -A test_vector_add=(
  ["function"]="test_vector_add"
  ["pass"]="CUDA vector_add example works."
)

declare -A test_cudnn=(
  ["function"]="test_cudnn"
  ["pass"]="cuDNN correctly applies sigmoid activation on a tensor."
)

declare -A test_cublas_batched=(
  ["function"]="test_cublas_batched"
  ["pass"]="Batched cublas works via test/cublas_batched.cu."
)

declare -A test_unified_mem=(
  ["function"]="test_unified_mem"
  ["pass"]="Unified memory works as expected."
)

#---- assign them to our associative array ----#
tests=("test_cuda_avail" "test_tensor_to_cuda" "test_tensor_to_cuda_to_cpu" "test_vector_add" "test_cudnn" "test_cublas_batched" "test_unified_mem")

test() {
  build

  echo -e "\n\033[1mRunning test(s)...\033[0m"

  for test in "${tests[@]}"; do
    func_name=$(eval "echo \${${test}[function]}")
    pass_message=$(eval "echo \${${test}[pass]}")

    if ! eval "$func_name \"$pass_message\""; then
      echo -e "\033[31mTest failed. Exiting...\033[0m"
      return 1
    fi
  done

  # if ./test/cuda-samples/bin doesn't exist, exit
  if [ ! -d "./test/cuda-samples/bin" ]; then
    echo -e "\033[31mCUDA samples not found. Exiting...\033[0m"
    return 1
  fi

  echo -e "\n\033[1mRunning compliance test(s)...\033[0m"

  # Path to the directory containing executables
  compliance_tests=(
    # "./test/cuda-samples/bin/x86_64/linux/release/MC_SingleAsianOptionP"
    # "./test/cuda-samples/bin/x86_64/linux/release/asyncAPI"
    "./test/cuda-samples/bin/x86_64/linux/release/c++11_cuda"
    "./test/cuda-samples/bin/x86_64/linux/release/vectorAdd"
    # "./test/cuda-samples/bin/x86_64/linux/release/streamOrderedAllocationIPC"
    # "./test/cuda-samples/bin/x86_64/linux/release/cuSolverDn_LinearSolver"
    # "./test/cuda-samples/bin/x86_64/linux/release/fastWalshTransform"
    # "./test/cuda-samples/bin/x86_64/linux/release/eigenvalues"
    # "./test/cuda-samples/bin/x86_64/linux/release/SobolQRNG"
    # "./test/cuda-samples/bin/x86_64/linux/release/convolutionFFT2D"
    # "./test/cuda-samples/bin/x86_64/linux/release/binaryPartitionCG"
    # "./test/cuda-samples/bin/x86_64/linux/release/sortingNetworks"
    # "./test/cuda-samples/bin/x86_64/linux/release/inlinePTX"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCUBLAS_LU"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleAttributes"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleAtomicIntrinsics"
    # "./test/cuda-samples/bin/x86_64/linux/release/UnifiedMemoryPerf"
    "./test/cuda-samples/bin/x86_64/linux/release/batchCUBLAS"
    # "./test/cuda-samples/bin/x86_64/linux/release/MC_EstimatePiInlineP"
    # "./test/cuda-samples/bin/x86_64/linux/release/vectorAddMMAP"
    # "./test/cuda-samples/bin/x86_64/linux/release/NV12toBGRandResize"
    # "./test/cuda-samples/bin/x86_64/linux/release/topologyQuery"
    # "./test/cuda-samples/bin/x86_64/linux/release/matrixMulCUBLAS"
    # "./test/cuda-samples/bin/x86_64/linux/release/cudaTensorCoreGemm"
    "./test/cuda-samples/bin/x86_64/linux/release/simplePrintf"
    # "./test/cuda-samples/bin/x86_64/linux/release/p2pBandwidthLatencyTest"
    # "./test/cuda-samples/bin/x86_64/linux/release/threadMigration"
    # "./test/cuda-samples/bin/x86_64/linux/release/batchedLabelMarkersAndLabelCompressionNPP"
    # "./test/cuda-samples/bin/x86_64/linux/release/mergeSort"
    # "./test/cuda-samples/bin/x86_64/linux/release/cppOverload"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleLayeredTexture"
    # "./test/cuda-samples/bin/x86_64/linux/release/nvJPEG"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCallback"
    # "./test/cuda-samples/bin/x86_64/linux/release/conjugateGradientMultiDeviceCG"
    # "./test/cuda-samples/bin/x86_64/linux/release/dwtHaar1D"
    # "./test/cuda-samples/bin/x86_64/linux/release/fp16ScalarProduct"
    # "./test/cuda-samples/bin/x86_64/linux/release/radixSortThrust"
    # "./test/cuda-samples/bin/x86_64/linux/release/cdpSimplePrint"
    # "./test/cuda-samples/bin/x86_64/linux/release/cuSolverSp_LinearSolver"
    # "./test/cuda-samples/bin/x86_64/linux/release/threadFenceReduction"
    # "./test/cuda-samples/bin/x86_64/linux/release/dct8x8"
    # "./test/cuda-samples/bin/x86_64/linux/release/scan"
    # "./test/cuda-samples/bin/x86_64/linux/release/cudaOpenMP"
    # "./test/cuda-samples/bin/x86_64/linux/release/alignedTypes"
    # "./test/cuda-samples/bin/x86_64/linux/release/cudaGraphsPerfScaling"
    # "./test/cuda-samples/bin/x86_64/linux/release/MersenneTwisterGP11213"
    # "./test/cuda-samples/bin/x86_64/linux/release/inlinePTX_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleIPC"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCUBLAS"
    # "./test/cuda-samples/bin/x86_64/linux/release/jacobiCudaGraphs"
    # "./test/cuda-samples/bin/x86_64/linux/release/watershedSegmentationNPP"
    # "./test/cuda-samples/bin/x86_64/linux/release/streamOrderedAllocation"
    # "./test/cuda-samples/bin/x86_64/linux/release/streamOrderedAllocationP2P"
    # "./test/cuda-samples/bin/x86_64/linux/release/newdelete"
    # "./test/cuda-samples/bin/x86_64/linux/release/clock_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleAssert_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/StreamPriorities"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleVoteIntrinsics"
    # "./test/cuda-samples/bin/x86_64/linux/release/shfl_scan"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleMultiGPU"
    # "./test/cuda-samples/bin/x86_64/linux/release/MonteCarloMultiGPU"
    # "./test/cuda-samples/bin/x86_64/linux/release/dxtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/jitLto"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCUFFT_2d_MGPU"
    # "./test/cuda-samples/bin/x86_64/linux/release/libcuhook.so.1"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleTemplates"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleMultiCopy"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCUBLASXT"
    # "./test/cuda-samples/bin/x86_64/linux/release/quasirandomGenerator"
    # "./test/cuda-samples/bin/x86_64/linux/release/vectorAddDrv"
    # "./test/cuda-samples/bin/x86_64/linux/release/cdpQuadtree"
    # "./test/cuda-samples/bin/x86_64/linux/release/reductionMultiBlockCG"
    # "./test/cuda-samples/bin/x86_64/linux/release/simplePitchLinearTexture"
    # "./test/cuda-samples/bin/x86_64/linux/release/cuSolverSp_LowlevelCholesky"
    # "./test/cuda-samples/bin/x86_64/linux/release/reduction"
    # "./test/cuda-samples/bin/x86_64/linux/release/cdpBezierTessellation"
    # "./test/cuda-samples/bin/x86_64/linux/release/binomialOptions_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/warpAggregatedAtomicsCG"
    # "./test/cuda-samples/bin/x86_64/linux/release/HSOpticalFlow"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleTexture"
    # "./test/cuda-samples/bin/x86_64/linux/release/concurrentKernels"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleAssert"
    # "./test/cuda-samples/bin/x86_64/linux/release/MC_EstimatePiP"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCUFFT_callback"
    # "./test/cuda-samples/bin/x86_64/linux/release/BlackScholes"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleDrvRuntime"
    # "./test/cuda-samples/bin/x86_64/linux/release/FDTD3d"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleTextureDrv"
    # "./test/cuda-samples/bin/x86_64/linux/release/graphMemoryNodes"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCubemapTexture"
    # "./test/cuda-samples/bin/x86_64/linux/release/matrixMul_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/memMapIPCDrv"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleTemplates_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/quasirandomGenerator_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/graphConditionalNodes"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleAtomicIntrinsics_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/transpose"
    # "./test/cuda-samples/bin/x86_64/linux/release/LargeKernelParameter"
    # "./test/cuda-samples/bin/x86_64/linux/release/ptxjit"
    # "./test/cuda-samples/bin/x86_64/linux/release/convolutionSeparable"
    # "./test/cuda-samples/bin/x86_64/linux/release/cuSolverSp_LowlevelQR"
    # "./test/cuda-samples/bin/x86_64/linux/release/cppIntegration"
    # "./test/cuda-samples/bin/x86_64/linux/release/conjugateGradientMultiBlockCG"
    # "./test/cuda-samples/bin/x86_64/linux/release/convolutionTexture"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleVoteIntrinsics_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/MC_EstimatePiInlineQ"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCudaGraphs"
    # "./test/cuda-samples/bin/x86_64/linux/release/MC_EstimatePiQ"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleSurfaceWrite"
    # "./test/cuda-samples/bin/x86_64/linux/release/scalarProd"
    # "./test/cuda-samples/bin/x86_64/linux/release/cudaCompressibleMemory"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleZeroCopy"
    # "./test/cuda-samples/bin/x86_64/linux/release/cdpSimpleQuicksort"
    # "./test/cuda-samples/bin/x86_64/linux/release/conjugateGradientUM"
    # "./test/cuda-samples/bin/x86_64/linux/release/histogram"
    # "./test/cuda-samples/bin/x86_64/linux/release/matrixMulDynlinkJIT"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleStreams"
    # "./test/cuda-samples/bin/x86_64/linux/release/UnifiedMemoryStreams"
    # "./test/cuda-samples/bin/x86_64/linux/release/immaTensorCoreGemm"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleOccupancy"
    # "./test/cuda-samples/bin/x86_64/linux/release/binomialOptions"
    # "./test/cuda-samples/bin/x86_64/linux/release/conjugateGradientCudaGraphs"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleSeparateCompilation"
    # "./test/cuda-samples/bin/x86_64/linux/release/clock"
    # "./test/cuda-samples/bin/x86_64/linux/release/bf16TensorCoreGemm"
    # "./test/cuda-samples/bin/x86_64/linux/release/segmentationTreeThrust"
    # "./test/cuda-samples/bin/x86_64/linux/release/tf32TensorCoreGemm"
    # "./test/cuda-samples/bin/x86_64/linux/release/deviceQueryDrv"
    # "./test/cuda-samples/bin/x86_64/linux/release/matrixMul"
    # "./test/cuda-samples/bin/x86_64/linux/release/stereoDisparity"
    # "./test/cuda-samples/bin/x86_64/linux/release/deviceQuery"
    # "./test/cuda-samples/bin/x86_64/linux/release/matrixMulDrv"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleHyperQ"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCUFFT"
    # "./test/cuda-samples/bin/x86_64/linux/release/cdpAdvancedQuicksort"
    # "./test/cuda-samples/bin/x86_64/linux/release/systemWideAtomics"
    # "./test/cuda-samples/bin/x86_64/linux/release/conjugateGradient"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCUFFT_MGPU"
    # "./test/cuda-samples/bin/x86_64/linux/release/bandwidthTest"
    # "./test/cuda-samples/bin/x86_64/linux/release/nvJPEG_encoder"
    # "./test/cuda-samples/bin/x86_64/linux/release/conjugateGradientPrecond"
    # "./test/cuda-samples/bin/x86_64/linux/release/BlackScholes_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/vectorAdd_nvrtc"
    # "./test/cuda-samples/bin/x86_64/linux/release/cuSolverRf"
    # "./test/cuda-samples/bin/x86_64/linux/release/dmmaTensorCoreGemm"
    # "./test/cuda-samples/bin/x86_64/linux/release/lineOfSight"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleP2P"
    # "./test/cuda-samples/bin/x86_64/linux/release/globalToShmemAsyncCopy"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleCooperativeGroups"
    # "./test/cuda-samples/bin/x86_64/linux/release/template"
    # "./test/cuda-samples/bin/x86_64/linux/release/simpleAWBarrier"
    # "./test/cuda-samples/bin/x86_64/linux/release/interval"
    # "./test/cuda-samples/bin/x86_64/linux/release/graphMemoryFootprint"
  )

  for test in "${compliance_tests[@]}"; do
    cd "$(dirname "$test")"

    # Run the script with a timeout and suppress stdout/stderr
    OUTPUT=$(LD_PRELOAD="$libscuda_path" ./$(basename "$test") 2>&1 | tr -d '\0')
    RET_CODE=$?

    if [[ $RET_CODE -ne 0 ]]; then
      # Print the output and error message
      echo "Error executing $test:"
      echo "$OUTPUT"
      echo "$ERROR_MSG"
    else
      ansi_format "pass" "$test"
    fi

    cd - > /dev/null
  done
}

build_tests() {
  build

  nvcc --cudart=shared -lnvidia-ml -lcuda ./test/vector_add.cu -o vector.o
  nvcc --cudart=shared -lnvidia-ml -lcuda -lcudnn ./test/cudnn.cu -o cudnn.o
  nvcc --cudart=shared -lnvidia-ml -lcuda -lcudnn -lcublas ./test/cublas_batched.cu -o cublas_batched.o
  nvcc --cudart=shared -lnvidia-ml -lcuda -lcudnn -lcublas ./test/unified.cu -o unified.o
  nvcc --cudart=shared -lnvidia-ml -lcuda -lcudnn -lcublas ./test/unified_pointer.cu -o unified_pointer.o
  nvcc --cudart=shared -lnvidia-ml -lcuda -lcudnn -lcublas ./test/unified_linked.cu -o unified_linked.o
  nvcc --cudart=shared -lnvidia-ml -lcuda -lcudnn -lcublas ./test/cublas_unified.cu -o cublas_unified.o
  nvcc --cudart=shared -lnvidia-ml -lcuda -lcudnn -lcublas ./test/cudnn_managed.cu -o cudnn_managed.o
}

run() {
  build

  export SCUDA_SERVER=0.0.0.0

  LD_PRELOAD="$libscuda_path" python3 -c "import torch; print(torch.cuda.is_available())"
}

# Main script logic using a switch case
case "$1" in
  build)
    build
    ;;
  build_tests)
    build_tests
    ;;
  run)
    run
    ;;
  server)
    server
    ;;
  test)
    test
    ;;
  *)
    echo "Usage: $0 {build|run|server}"
    exit 1
    ;;
esac
