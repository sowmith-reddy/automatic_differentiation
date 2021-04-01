
#include "./c_runtime_api.h"
#include <cassert>
#include <cstdio>
#include <cublas_v2.h>
#include <cuda_runtime.h>

/* TODO: Your code here */
/* all your GPU kernel code, e.g. matrix_softmax_cross_entropy_kernel */

// y = inputs[0], y_ = inputs[1]
// np.mean(-np.sum(y_ * np.log(softmax(y)), axis=1), keepdims=True)
__global__ void matrix_softmax_cross_entropy_kernel(int nrow, int ncol,
                                                    const float *input_a,
                                                    const float *input_b,
                                                    float *output) {
  // Dynamic shared memory, size provided at kernel launch.
    extern __shared__ float loss_per_row[];
  // Two dimensional thread blocks.
    int y = blockIdx.x * blockDim.x * blockDim.y + threadIdx.y * blockDim.x + threadIdx.x;
    if (y >= nrow) {
        return;
    }
    input_a += y * ncol;
    input_b += y * ncol;
    float maxval = *input_a;
  // Find max for a row.
    for (int x = 1; x < ncol; ++x) {
        maxval = max(maxval, input_a[x]);
    }
  // Deduct by max for a row, and raise to exp.
    float sum = 0;
    for (int x = 0; x < ncol; ++x) {
        sum += exp(input_a[x] - maxval);
    }
  // Compute per-row loss.
    float loss = 0;
    for (int x = 0; x < ncol; ++x) {
        loss -= input_b[x] * log(exp(input_a[x] - maxval) / sum);
    }
    loss_per_row[y] = loss;
    __syncthreads();
  // Compute reduce_mean across rows.
    float mean_loss = 0;
  // Use a single thread to reduce mean across rows.
    if ((threadIdx.x == 0) && (threadIdx.y == 0)) {
        for (int i = 0; i < nrow; ++i) {
            mean_loss += loss_per_row[i];
        }
        mean_loss /= nrow;
        output[0] = mean_loss;
    }
}

int DLGpuSoftmaxCrossEntropy(const DLArrayHandle input_a,
                             const DLArrayHandle input_b,
                             DLArrayHandle output) {
    assert(input_a->ndim == 2);
    assert(input_b->ndim == 2);
    assert(output->ndim == 1);
    assert(input_a->shape[0] == input_b->shape[0] && input_a->shape[1] == input_b->shape[1]);
    int nrow = input_a->shape[0];
  // Maximum x- or y-dimension of a block = 1024
  // But we need 'nrow' shared memory, and max shared memory is 48KB.
  // Conservatively allow max 16KB shared memory.
    assert(nrow <= 1024 * 4);
    int ncol = input_a->shape[1];
    const float *input_data_a = (const float *)input_a->data;
    const float *input_data_b = (const float *)input_b->data;
    float *output_data = (float *)output->data;
    dim3 threads;
    if (nrow <= 1024) {
        threads.x = nrow;
    }
    else {
        threads.x = 1024;
        threads.y = (nrow + 1023) / 1024;
    }
  // 1 block, each block with 'threads' number of threads with 'nrow' shared
  // memory size
    matrix_softmax_cross_entropy_kernel<<<1, threads, nrow * sizeof(float)>>>(
        nrow, ncol, input_data_a, input_data_b, output_data);
    return 0;
}

__global__ void arrayset_kernel_function(int n, float *array_data, float value) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= n) {
        return;
    }
    array_data[y] = value;
}

int DLGpuArraySet(DLArrayHandle arr, float value) { /* TODO: Your code here */
    int n = 1;
    for (int i = 0; i < arr->ndim; i++) {
        n *= arr->shape[i];
    }
    float *array_data = (float *)arr->data;
    dim3 threads;
    dim3 blocks;
    if (n > 1024) {
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;
    }
    else {
        threads.x = n;
        blocks.x = 1;
    }
    arrayset_kernel_function<<<blocks, threads>>>(n, array_data, value);
    return 0;
}

__global__ void broadcast_kernel_function(int n, int out, const float *input_data, float *output_data) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= n) {
        return;
    }
    for (int i = y; i < out;i += n) {
        output_data[i] = input_data[y];
    }
}

int DLGpuBroadcastTo(const DLArrayHandle input, DLArrayHandle output) {
  /* TODO: Your code here */
    int n = 1;
    for (int i = 0; i < input->ndim; i++) {
        n *= input->shape[i];
    }
    dim3 blocks;
    dim3 threads;
    int out = 1;
    for (int i = 0; i < output->ndim; i++) {
        out *= output->shape[i];
    }
    float *output_data = (float *)output->data;
    const float *input_data = (const float *)input->data;
     if (n <= 1024) {

        threads.x = n;
        blocks.x = 1;    }
    else {
        
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;

    }
    broadcast_kernel_function<<<blocks, threads>>>(n, out, input_data, output_data);
    return 0;
}

__global__ void reduceSumAxisZero_kernel_function(int n, int out, const float *input_data, float *output_data) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= out) {
        return;
    }
    output_data[y] = 0;
    for (int i = y; i < n; i += out) {
        output_data[y] += input_data[i];
    }
}


int DLGpuReduceSumAxisZero(const DLArrayHandle input, DLArrayHandle output) {
  /* TODO: Your code here */
    int n =1;
    for (int i = 0; i < input->ndim; i++) {
        n *= input->shape[i];
    }
    int out = 1;
    for (int i = 0; i < output->ndim; i++) {
        out *= output->shape[i];
    }
    dim3 blocks;
    dim3 threads;
    float *output_data = (float *)output->data;
    const float *input_data = (const float *)input->data;
     if (n <= 1024) {

        threads.x = n;
        blocks.x = 1;    }
    else {
        
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;

    }
    reduceSumAxisZero_kernel_function<<<blocks, threads>>>(n, out, input_data, output_data);
    return 0;
}

__global__ void matrixAdd_kernel_function(int n, const float *input_data_a, const float *input_data_b, float *output_data) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= n) {
        return;
    }
    output_data[y] = input_data_a[y] + input_data_b[y];
}

int DLGpuMatrixElementwiseAdd(const DLArrayHandle matA,
                              const DLArrayHandle matB, DLArrayHandle output) {
  /* TODO: Your code here */
    int n = 1;
    dim3 blocks;
    dim3 threads;
    for (int i = 0; i < matA->ndim; i++) {
        n *= matA->shape[i];
    }
    
    const float *input_data_a = (const float *)matA->data;

    const float *input_data_b = (const float *)matB->data;

    float *output_data = (float *)output->data;
     if (n <= 1024) {

        threads.x = n;
        blocks.x = 1;    }
    else {
        
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;

    }
    matrixAdd_kernel_function<<<blocks, threads>>>(n, input_data_a, input_data_b, output_data);
    return 0;
}

__global__ void matrixElementWiseAddByConst_kernel_function(int n, const float *input_data, float val, float *output_data) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= n) {
        return;
    }
    output_data[y] = input_data[y] + val;
}

int DLGpuMatrixElementwiseAddByConst(const DLArrayHandle input, float val,
                                     DLArrayHandle output) {
  /* TODO: Your code here */
    int n = 1;
    for (int i = 0; i < input->ndim; i++) {
        n *= input->shape[i];
    }
    dim3 blocks;
    dim3 threads;
    float *output_data = (float *)output->data;
    const float *input_data = (const float *)input->data;
    if (n <= 1024) {
        threads.x = n;
        blocks.x = 1;
    }
    else {
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;
    }
    matrixElementWiseAddByConst_kernel_function<<<blocks, threads>>>(n, input_data, val, output_data);
    return 0;
}

__global__ void matrixElementWiseMultiply_kernel_function(int n, const float *input_data_a, const float *input_data_b, float *output_data) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= n) {
        return;
    }
    output_data[y] = input_data_a[y] * input_data_b[y];
}

int DLGpuMatrixElementwiseMultiply(const DLArrayHandle matA,
                                   const DLArrayHandle matB,
                                   DLArrayHandle output) {
  /* TODO: Your code here */
    int n = 1;
     dim3 blocks;
    dim3 threads;
    for (int i = 0; i < matA->ndim; i++) {
        n *= matA->shape[i];
    }
   
    float *output_data = (float *)output->data;

    const float *input_data_a = (const float *)matA->data;

    const float *input_data_b = (const float *)matB->data;
     if (n <= 1024) {

        threads.x = n;
        blocks.x = 1;    }
    else {
        
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;

    }
    matrixElementWiseMultiply_kernel_function<<<blocks, threads>>>(n, input_data_a, input_data_b, output_data);
    return 0;
}

__global__ void matrixMulByConst_kernel_function(int n, const float *input_data, float val, float *output_data) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= n) {
        return;
    }
    output_data[y] = input_data[y] * val;
}

int DLGpuMatrixMultiplyByConst(const DLArrayHandle input, float val,
                               DLArrayHandle output) {
  /* TODO: Your code here */
    int n = 1;
    for (int i = 0; i < input->ndim; i++) {
        n *= input->shape[i];
    }
    dim3 blocks;
    dim3 threads;
    float *output_data = (float *)output->data;
    const float *input_data = (const float *)input->data;
     if (n <= 1024) {

        threads.x = n;
        blocks.x = 1;    }
    else {
        
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;

    }
    matrixMulByConst_kernel_function<<<blocks, threads>>>(n, input_data, val, output_data);
    return 0;
}

__global__ void MatrixMultiply_kernel_function(const float *A, const float *B, float *C, int rowA, int colA, int rowB, int colB, bool transA, bool transB) {
    float Cvalue = 0.0;
    int r = blockIdx.y * blockDim.y + threadIdx.y;
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    if(!transA && !transB){
        assert(colA == rowB);
        if(r >= rowA || c >= colB) return;
        for (int e = 0; e < colA; ++e)
            Cvalue += (A[r * colA + e]) * (B[e * colB + c]);
        C[r * colB + c] = Cvalue;
    }else if(transA && !transB){
        if(r >= colA || c >= colB) return;
        for (int e = 0; e < rowA; ++e)
            Cvalue += (A[e * colA + r]) * (B[e * colB + c]);
        C[r * colB + c] = Cvalue;
    }else if(!transA && transB){
        if(r >= rowA || c >= rowB) return;
        for (int e = 0; e < colA; ++e)
            Cvalue += (A[r * colA + e]) * (B[c * colB + e]);
        C[r * rowB + c] = Cvalue;
    }else if(transA && transB){
        if(r >= colA || c >= rowB) return;
        for (int e = 0; e < rowA; ++e)
            Cvalue += (A[e * colA + r]) * (B[c * colB + e]);
        C[r * rowB + c] = Cvalue;
    }
}

int DLGpuMatrixMultiply(const DLArrayHandle matA, bool transposeA,
                        const DLArrayHandle matB, bool transposeB,
                        DLArrayHandle matC) {
  /* TODO: Your code here */
  // Hint: use cublas
  // cublas assume matrix is column major
    int rowA = matA->shape[0];
    int colA = matA->shape[1];
    int rowB = matB->shape[0];
    int colB = matB->shape[1];

    const float *matA_data = (const float *)matA->data;
    const float *matB_data = (const float *)matB->data;

    float *matC_data = (float *)matC->data;
    
    const int BLOCK_SIZE = 16;

    dim3 dimBlock(BLOCK_SIZE, BLOCK_SIZE);
    dim3 dimGrid((max(rowB, colB) + dimBlock.x - 1) / dimBlock.x,
            (max(rowA, colA) + dimBlock.y - 1) / dimBlock.y);
    MatrixMultiply_kernel_function<<<dimGrid, dimBlock>>>(matA_data, matB_data, matC_data, rowA, colA, rowB, colB, transposeA, transposeB);
    return 0;
}


__global__ void relu_kernel_function(int n, const float *input_data, float *output_data) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= n) {
        return;
    }
    if (input_data[y] > 0.0) {
        output_data[y] = input_data[y];
    }
    else {
        output_data[y] = 0.0;
    }
}

int DLGpuRelu(const DLArrayHandle input, DLArrayHandle output) {
  /* TODO: Your code here */
    int n = 1;
    for (int i = 0; i < input->ndim; i++) {
        n *= input->shape[i];
    }
    dim3 blocks;
    dim3 threads;
    float *output_data = (float *)output->data;
    const float *input_data = (const float *)input->data;
     if (n <= 1024) {

        threads.x = n;
        blocks.x = 1;    }
    else {
        
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;

    }
    relu_kernel_function<<<blocks, threads>>>(n, input_data, output_data);
    return 0;

}

__global__ void reluGradient_kernel_function(int n, const float *input_data, const float *in_grad_data, float *output_data) {
    int y = blockIdx.x * blockDim.x + threadIdx.x;
    if (y >= n) {
        return;
    }
    if (input_data[y] > 0.0) {
        output_data[y] = in_grad_data[y];
    }
    else {
        output_data[y] = 0.0;
    }
}

int DLGpuReluGradient(const DLArrayHandle input, const DLArrayHandle in_grad,
                      DLArrayHandle output) {
  /* TODO: Your code here */
    int n = 1;
    for (int i = 0; i < input->ndim; i++) {
        n *= input->shape[i];
    }
    float *output_data = (float *)output->data;
    const float *input_data = (const float *)input->data;
    const float *in_grad_data = (const float *)in_grad->data;

    dim3 blocks;
    dim3 threads;
    
    if (n <= 1024) {

        threads.x = n;
        blocks.x = 1;    }
    else {
        
        threads.x = 1024;
        blocks.x = (n + 1023) / 1024;

    }
    reluGradient_kernel_function<<<blocks, threads>>>(n, input_data, in_grad_data, output_data);
    return 0;

}

__global__ void matrixSoftmax_kernel_function(int nrow, int ncol, const float *input_data, float *output_data) {
    /*int y = blockIdx.x * blockDim.x * blockDim.y + threadIdx.y * blockDim.x + threadIdx.x;*/
    int y = threadIdx.y * blockDim.x + threadIdx.x;
    if (y >= nrow) {
        return;
    }
    input_data += y * ncol;
    output_data += y * ncol;
    float maxval = *input_data;
    // Find max for a row.
    for (int x = 1; x < ncol; ++x) {
        maxval = max(maxval, input_data[x]);
    }
    // Deduct by max for a row, and raise to exp.
    float sum = 0;
    for (int x = 0; x < ncol; ++x) {
        sum += exp(input_data[x] - maxval);
    }
    for (int x = 0; x < ncol; ++x) {
        output_data[x] = exp(input_data[x] - maxval) / sum;
    }
}

int DLGpuSoftmax(const DLArrayHandle input, DLArrayHandle output) {
  /* TODO: Your code here */
    assert(input->ndim == 2);
    int nrow = input->shape[0];
  // Maximum x- or y-dimension of a block = 1024
  // But we need 'nrow' shared memory, and max shared memory is 48KB.
  // Conservatively allow max 16KB shared memory.
    assert(nrow <= 1024 * 4);
    int ncol = input->shape[1];
    const float *input_data = (const float *)input->data;
    float *output_data = (float *)output->data;
    dim3 threads;
    if (nrow <= 1024) {
        threads.x = nrow;
    }
    else {
        threads.x = 1024;
        threads.y = (nrow + 1023) / 1024;
    }
  // 1 block, each block with 'threads' number of threads with 'nrow' shared
  // memory size
    matrixSoftmax_kernel_function<<<1, threads>>>(nrow, ncol, input_data, output_data);
    return 0;
}