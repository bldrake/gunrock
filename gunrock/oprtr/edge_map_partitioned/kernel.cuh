// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------


/**
 * @file
 * kernel.cuh
 *
 * @brief Load balanced Edge Map Kernel Entrypoint
 */

#pragma once
#include <gunrock/util/cta_work_distribution.cuh>
#include <gunrock/util/cta_work_progress.cuh>
#include <gunrock/util/kernel_runtime_stats.cuh>

#include <gunrock/oprtr/edge_map_partitioned/cta.cuh>

namespace gunrock {
namespace oprtr {
namespace edge_map_partitioned {

// GetRowOffsets
//
// RelaxPartitionedEdges

/**
 * Arch dispatch
 */

/**
 * Not valid for this arch (default)
 */
template<
    typename    KernelPolicy,
    typename    ProblemData,
    typename    Functor,
    bool        VALID = (__GR_CUDA_ARCH__ >= KernelPolicy::CUDA_ARCH)>
struct Dispatch
{
    typedef typename KernelPolicy::VertexId VertexId;
    typedef typename KernelPolicy::SizeT    SizeT;
    typedef typename ProblemData::DataSlice DataSlice;

    static __device__ __forceinline__ SizeT GetNeighborListLength(
                            VertexId    *&d_row_offsets,
                            VertexId    &d_vertex_id,
                            SizeT       &max_vertex,
                            SizeT       &max_edge)
    {
    }

    static __device__ __forceinline__ void GetEdgeCounts(
                                SizeT *&d_row_offsets,
                                VertexId *&d_queue,
                                unsigned int *&d_scanned_edges,
                                SizeT &num_elements,
                                SizeT &max_vertex,
                                SizeT &max_edge)
    {
    }

    static __device__ __forceinline__ void RelaxPartitionedEdges(
                                bool &queue_reset,
                                VertexId &queue_index,
                                int &label,
                                SizeT *&d_row_offsets,
                                VertexId *&d_column_indices,
                                unsigned int *&d_scanned_edges,
                                unsigned int *&partition_starts,
                                unsigned int &num_partitions,
                                volatile int *&d_done,
                                VertexId *&d_queue,
                                VertexId *&d_out,
                                DataSlice *&problem,
                                SizeT &input_queue_len,
                                SizeT &output_queue_len,
                                SizeT &partition_size,
                                SizeT &max_vertices,
                                SizeT &max_edges,
                                util::CtaWorkProgress &work_progress,
                                util::KernelRuntimeStats &kernel_stats)
    {
    }

    static __device__ __forceinline__ void RelaxLightEdges(
                                bool &queue_reset,
                                VertexId &queue_index,
                                int &label,
                                SizeT *&d_row_offsets,
                                VertexId *&d_column_indices,
                                unsigned int *&d_scanned_edges,
                                volatile int *&d_done,
                                VertexId *&d_queue,
                                VertexId *&d_out,
                                DataSlice *&problem,
                                SizeT &input_queue_len,
                                SizeT &output_queue_len,
                                SizeT &max_vertices,
                                SizeT &max_edges,
                                util::CtaWorkProgress &work_progress,
                                util::KernelRuntimeStats &kernel_stats)
    {
    }

};
template <typename KernelPolicy, typename ProblemData, typename Functor>
struct Dispatch<KernelPolicy, ProblemData, Functor, true>
{
    typedef typename KernelPolicy::VertexId         VertexId;
    typedef typename KernelPolicy::SizeT            SizeT;
    typedef typename ProblemData::DataSlice         DataSlice;

    static __device__ __forceinline__ SizeT GetNeighborListLength(
                            VertexId    *&d_row_offsets,
                            VertexId    &d_vertex_id,
                            SizeT       &max_vertex,
                            SizeT       &max_edge)
    {
        SizeT first = d_vertex_id >= max_vertex ? max_edge : d_row_offsets[d_vertex_id];
        SizeT second = (d_vertex_id + 1) >= max_vertex ? max_edge : d_row_offsets[d_vertex_id+1];

        return (second > first) ? second - first : 0;
    }

    static __device__ __forceinline__ void GetEdgeCounts(
                                SizeT *&d_row_offsets,
                                VertexId *&d_queue,
                                unsigned int *&d_scanned_edges,
                                SizeT &num_elements,
                                SizeT &max_vertex,
                                SizeT &max_edge)
    {
        int tid = threadIdx.x;
        int bid = blockIdx.x;

        int my_id = bid*blockDim.x + tid;
        if (my_id >= num_elements || my_id >= max_edge)
            return;
        VertexId v_id = d_queue[my_id];
        SizeT num_edges = GetNeighborListLength(d_row_offsets, v_id, max_vertex, max_edge);
        d_scanned_edges[my_id] = num_edges;
    }

    static __device__ __forceinline__ void RelaxPartitionedEdges(
                                bool &queue_reset,
                                VertexId &queue_index,
                                int &label,
                                SizeT *&d_row_offsets,
                                VertexId *&d_column_indices,
                                unsigned int *&d_scanned_edges,
                                unsigned int *&partition_starts,
                                unsigned int &num_partitions,
                                volatile int *&d_done,
                                VertexId *&d_queue,
                                VertexId *&d_out,
                                DataSlice *&problem,
                                SizeT &input_queue_len,
                                SizeT &output_queue_len,
                                SizeT &partition_size,
                                SizeT &max_vertices,
                                SizeT &max_edges,
                                util::CtaWorkProgress &work_progress,
                                util::KernelRuntimeStats &kernel_stats)
    {
        if (KernelPolicy::INSTRUMENT && (threadIdx.x == 0 && blockIdx.x == 0)) {
            kernel_stats.MarkStart();
        }

        // Reset work progress
        if (queue_reset)
        {
            if (blockIdx.x == 0 && threadIdx.x < util::CtaWorkProgress::COUNTERS) {
                //Reset all counters
                work_progress.template Reset<SizeT>();
            }
        }

        // Determine work decomposition
        if (threadIdx.x == 0 && blockIdx.x == 0) {

            // obtain problem size
            if (queue_reset)
            {
                work_progress.StoreQueueLength<SizeT>(input_queue_len, queue_index);
            }
            else
            {
                input_queue_len = work_progress.template LoadQueueLength<SizeT>(queue_index);
                
                // Signal to host that we're done
                if (input_queue_len == 0) {
                    if (d_done) d_done[0] = input_queue_len;
                }
            }

            work_progress.Enqueue(output_queue_len, queue_index+1);

            // Reset our next outgoing queue counter to zero
            work_progress.template StoreQueueLength<SizeT>(0, queue_index + 2);
            work_progress.template PrepResetSteal<SizeT>(queue_index + 1);
        }

        // Barrier to protect work decomposition
        __syncthreads();

        int tid = threadIdx.x;
        int bid = blockIdx.x;

        int my_thread_start, my_thread_end;

        my_thread_start = bid * partition_size;
        my_thread_end = (bid+1)*partition_size < output_queue_len ? (bid+1)*partition_size : output_queue_len;

        if (my_thread_start >= output_queue_len)
            return;

        int my_start_partition = partition_starts[bid];
        int my_end_partition = bid < num_partitions - 1 ? partition_starts[bid+1]+1 : input_queue_len;

        __shared__ typename KernelPolicy::SmemStorage smem_storage;
        // smem_storage.s_edges[NT]
        // smem_storage.s_vertices[NT]
        unsigned int* s_edges = (unsigned int*) &smem_storage.s_edges[0];
        unsigned int* s_vertices = (unsigned int*) &smem_storage.s_vertices[0];

        int my_work_size = my_thread_end - my_thread_start;
        int out_offset = bid * partition_size;
        int pre_offset = my_start_partition > 0 ? d_scanned_edges[my_start_partition-1] : 0;
        int e_offset = my_thread_start - pre_offset;
        int edges_processed = 0;

        while (edges_processed < my_work_size && my_start_partition < my_end_partition)
        {
            pre_offset = my_start_partition > 0 ? d_scanned_edges[my_start_partition-1] : 0;

            __syncthreads();

            s_edges[tid] = (my_start_partition + tid < my_end_partition ? d_scanned_edges[my_start_partition + tid] - pre_offset : max_edges);
            s_vertices[tid] = my_start_partition + tid < my_end_partition ? d_queue[my_start_partition+tid] : -1;

            int last = my_start_partition + KernelPolicy::THREADS >= my_end_partition ? my_end_partition - my_start_partition - 1 : KernelPolicy::THREADS - 1;

            __syncthreads();

            SizeT e_last = min(s_edges[last] - e_offset, my_work_size - edges_processed);
            SizeT v_index = BinarySearch<KernelPolicy::THREADS>(tid+e_offset, s_edges);
            VertexId v = s_vertices[v_index];
            SizeT end_last = (v_index < my_end_partition ? s_edges[v_index] : max_edges);
            SizeT internal_offset = v_index > 0 ? s_edges[v_index-1] : 0;
            SizeT lookup_offset = d_row_offsets[v];

            for (int i = (tid + e_offset); i < e_last + e_offset; i+=KernelPolicy::THREADS)
            {
                if (i >= end_last)
                {
                    v_index = BinarySearch<KernelPolicy::THREADS>(i, s_edges);
                    v = d_queue[v_index];
                    end_last = (v_index < KernelPolicy::THREADS ? s_edges[v_index] : max_edges);
                    internal_offset = v_index > 0 ? s_edges[v_index-1] : 0;
                    lookup_offset = d_row_offsets[v];
                }

                int e = i - internal_offset;
                int lookup = lookup_offset + e;
                VertexId u = d_column_indices[lookup];
                SizeT out_index = out_offset+edges_processed+(i-e_offset);

                /*if (label == 1) {
                    if (!ProblemData::MARK_PREDECESSORS) {
                        if (Functor::CondEdge(label, u, problem)) {
                            Functor::ApplyEdge(label, u, problem);
                            util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                                    (int)s_edges[0],
                                    d_out + out_index);
                        }
                        else {
                            util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                                    (int)s_edges[0],
                                    d_out + out_index);
                        }
                    }
                } else*/
                {
                    if (!ProblemData::MARK_PREDECESSORS) {
                        if (Functor::CondEdge(label, u, problem, lookup)) {
                            Functor::ApplyEdge(label, u, problem, lookup);
                            util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                                    u,
                                    d_out + out_index);
                        }
                        else {
                            util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                                    -1,
                                    d_out + out_index);
                        }
                    } else {
                        if (Functor::CondEdge(v, u, problem, lookup)) {
                            Functor::ApplyEdge(v, u, problem, lookup);
                            util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                                    u,
                                    d_out + out_index);
                        }
                        else {
                            util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                                    -1,
                                    d_out + out_index);
                        }
                    }
                }

            }
            edges_processed += e_last;
            my_start_partition += KernelPolicy::THREADS;
            e_offset = 0;
        }

        if (KernelPolicy::INSTRUMENT && (blockIdx.x == 0 && threadIdx.x == 0)) {
            kernel_stats.MarkStop();
            kernel_stats.Flush();
        }
    }

    static __device__ __forceinline__ void RelaxLightEdges(
                                bool &queue_reset,
                                VertexId &queue_index,
                                int &label,
                                SizeT *&d_row_offsets,
                                VertexId *&d_column_indices,
                                unsigned int *&d_scanned_edges,
                                volatile int *&d_done,
                                VertexId *&d_queue,
                                VertexId *&d_out,
                                DataSlice *&problem,
                                SizeT &input_queue_len,
                                SizeT &output_queue_len,
                                SizeT &max_vertices,
                                SizeT &max_edges,
                                util::CtaWorkProgress &work_progress,
                                util::KernelRuntimeStats &kernel_stats)
    {
        if (KernelPolicy::INSTRUMENT && (blockIdx.x == 0 && threadIdx.x == 0)) {
            kernel_stats.MarkStart();
        }

        // Reset work progress
        if (queue_reset)
        {
            if (blockIdx.x == 0 && threadIdx.x < util::CtaWorkProgress::COUNTERS) {
                //Reset all counters
                work_progress.template Reset<SizeT>();
            }
        }

        // Determine work decomposition
        if (blockIdx.x == 0 && threadIdx.x == 0) {

            // obtain problem size
            if (queue_reset)
            {
                work_progress.StoreQueueLength<SizeT>(input_queue_len, queue_index);
            }
            else
            {
                input_queue_len = work_progress.template LoadQueueLength<SizeT>(queue_index);
                
                // Signal to host that we're done
                if (input_queue_len == 0) {
                    if (d_done) d_done[0] = input_queue_len;
                }
            }

            work_progress.Enqueue(output_queue_len, queue_index+1);

            // Reset our next outgoing queue counter to zero
            work_progress.template StoreQueueLength<SizeT>(0, queue_index + 2);
            work_progress.template PrepResetSteal<SizeT>(queue_index + 1);
        }

        // Barrier to protect work decomposition
        __syncthreads();

        unsigned int range = input_queue_len;
        int tid = threadIdx.x;
        int bid = blockIdx.x;
        int my_id = bid * KernelPolicy::THREADS + tid;


        __shared__ typename KernelPolicy::SmemStorage smem_storage;
        unsigned int* s_edges = (unsigned int*) &smem_storage.s_edges[0];
        unsigned int* s_vertices = (unsigned int*) &smem_storage.s_vertices[0];

        int offset = (KernelPolicy::THREADS*bid - 1) > 0 ? d_scanned_edges[KernelPolicy::THREADS*bid-1] : 0;
        int end_id = (KernelPolicy::THREADS*(bid+1)) >= range ? range - 1 : KernelPolicy::THREADS*(bid+1) - 1;

        end_id = end_id % KernelPolicy::THREADS;
        s_edges[tid] = (my_id < range ? d_scanned_edges[my_id] - offset : max_edges);
        s_vertices[tid] = (my_id < range ? d_queue[my_id] : max_vertices);

        __syncthreads();
        unsigned int size = s_edges[end_id];

        VertexId v, e;

        int v_index = BinarySearch<KernelPolicy::THREADS>(tid, s_edges);
        v = s_vertices[v_index];
        int end_last = (v_index < KernelPolicy::THREADS ? s_edges[v_index] : max_vertices);

        for (int i = tid; i < size; i += KernelPolicy::THREADS)
        {
            if (i >= end_last)
            {
                v_index = BinarySearch<KernelPolicy::THREADS>(i, s_edges);
                v = s_vertices[v_index];
                end_last = (v_index < KernelPolicy::THREADS ? s_edges[v_index] : max_vertices);
            }

            int internal_offset = v_index > 0 ? s_edges[v_index-1] : 0;
            e = i - internal_offset;

            int lookup = d_row_offsets[v] + e;
            VertexId u = d_column_indices[lookup];
           
            if (!ProblemData::MARK_PREDECESSORS) {
                if (Functor::CondEdge(label, u, problem, lookup)) {
                    Functor::ApplyEdge(label, u, problem, lookup);
                    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                            u,
                            d_out + offset+i);
                }
                else {
                    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                            -1,
                            d_out + offset+i);
                }
            } else {
                //v:pre, u:neighbor, outoffset:offset+i
                if (Functor::CondEdge(v, u, problem, lookup)) {
                    Functor::ApplyEdge(v, u, problem, lookup);
                    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                            u,
                            d_out + offset+i);
                }
                else {
                    util::io::ModifiedStore<ProblemData::QUEUE_WRITE_MODIFIER>::St(
                            -1,
                            d_out + offset+i);
                }
            }
        }

        if (KernelPolicy::INSTRUMENT && (blockIdx.x == 0 && threadIdx.x == 0)) {
            kernel_stats.MarkStop();
            kernel_stats.Flush();
        }
    }

};

/**
 * @brief Kernel entry for relax partitioned edge function
 *
 * @tparam KernelPolicy Kernel policy type for partitioned edge mapping.
 * @tparam ProblemData Problem data type for partitioned edge mapping.
 * @tparam Functor Functor type for the specific problem type.
 *
 * @param[in] queue_reset       If reset queue counter
 * @param[in] queue_index       Current frontier queue counter index
 * @param[in] d_row_offset      Device pointer of SizeT to the row offsets queue
 * @param[in] d_column_indices  Device pointer of VertexId to the column indices queue
 * @param[in] d_scanned_edges   Device pointer of scanned neighbor list queue of the current frontier
 * @param[in] partition_starts  Device pointer of partition start index computed by sorted search in moderngpu lib
 * @param[in] num_partitions    Number of partitions in the current frontier
 * @param[in] d_done            Pointer of volatile int to the flag to set when we detect incoming frontier is empty
 * @param[in] d_queue           Device pointer of VertexId to the incoming frontier queue
 * @param[out] d_out            Device pointer of VertexId to the outgoing frontier queue
 * @param[in] problem           Device pointer to the problem object
 * @param[in] input_queue_len   Length of the incoming frontier queue
 * @param[in] output_queue_len  Length of the outgoing frontier queue
 * @param[in] max_vertices      Maximum number of elements we can place into the incoming frontier
 * @param[in] max_edges         Maximum number of elements we can place into the outgoing frontier
 * @param[in] work_progress     queueing counters to record work progress
 * @param[in] kernel_stats      Per-CTA clock timing statistics (used when KernelPolicy::INSTRUMENT is set)
 */
    template <typename KernelPolicy, typename ProblemData, typename Functor>
__launch_bounds__ (KernelPolicy::THREADS, KernelPolicy::CTA_OCCUPANCY)
    __global__
void RelaxPartitionedEdges(
        bool                                    queue_reset,
        typename KernelPolicy::VertexId         queue_index,
        int                                     label,
        typename KernelPolicy::SizeT            *d_row_offsets,
        typename KernelPolicy::VertexId         *d_column_indices,
        unsigned int                            *d_scanned_edges,
        unsigned int                            *partition_starts,
        unsigned int                            num_partitions,
        volatile int                            *d_done,
        typename KernelPolicy::VertexId         *d_queue,
        typename KernelPolicy::VertexId         *d_out,
        typename ProblemData::DataSlice         *problem,
        typename KernelPolicy::SizeT            input_queue_len,
        typename KernelPolicy::SizeT            output_queue_len,
        typename KernelPolicy::SizeT            partition_size,
        typename KernelPolicy::SizeT            max_vertices,
        typename KernelPolicy::SizeT            max_edges,
        util::CtaWorkProgress                   work_progress,
        util::KernelRuntimeStats                kernel_stats)
{
    Dispatch<KernelPolicy, ProblemData, Functor>::RelaxPartitionedEdges(
            queue_reset,
            queue_index,
            label,
            d_row_offsets,
            d_column_indices,
            d_scanned_edges,
            partition_starts,
            num_partitions,
            d_done,
            d_queue,
            d_out,
            problem,
            input_queue_len,
            output_queue_len,
            partition_size,
            max_vertices,
            max_edges,
            work_progress,
            kernel_stats);
}

/**
 * @brief Kernel entry for relax light edge function
 *
 * @tparam KernelPolicy Kernel policy type for partitioned edge mapping.
 * @tparam ProblemData Problem data type for partitioned edge mapping.
 * @tparam Functor Functor type for the specific problem type.
 *
 * @param[in] queue_reset       If reset queue counter
 * @param[in] queue_index       Current frontier queue counter index
 * @param[in] d_row_offset      Device pointer of SizeT to the row offsets queue
 * @param[in] d_column_indices  Device pointer of VertexId to the column indices queue
 * @param[in] d_scanned_edges   Device pointer of scanned neighbor list queue of the current frontier
 * @param[in] d_done            Pointer of volatile int to the flag to set when we detect incoming frontier is empty
 * @param[in] d_queue           Device pointer of VertexId to the incoming frontier queue
 * @param[out] d_out            Device pointer of VertexId to the outgoing frontier queue
 * @param[in] problem           Device pointer to the problem object
 * @param[in] input_queue_len   Length of the incoming frontier queue
 * @param[in] output_queue_len  Length of the outgoing frontier queue
 * @param[in] max_vertices      Maximum number of elements we can place into the incoming frontier
 * @param[in] max_edges         Maximum number of elements we can place into the outgoing frontier
 * @param[in] work_progress     queueing counters to record work progress
 * @param[in] kernel_stats      Per-CTA clock timing statistics (used when KernelPolicy::INSTRUMENT is set)
 */
    template <typename KernelPolicy, typename ProblemData, typename Functor>
__launch_bounds__ (KernelPolicy::THREADS, KernelPolicy::CTA_OCCUPANCY)
    __global__
void RelaxLightEdges(
        bool                            queue_reset,
        typename KernelPolicy::VertexId queue_index,
        int                             label,
        typename KernelPolicy::SizeT    *d_row_offsets,
        typename KernelPolicy::VertexId *d_column_indices,
        unsigned int    *d_scanned_edges,
        volatile int                    *d_done,
        typename KernelPolicy::VertexId *d_queue,
        typename KernelPolicy::VertexId *d_out,
        typename ProblemData::DataSlice *problem,
        typename KernelPolicy::SizeT    input_queue_len,
        typename KernelPolicy::SizeT    output_queue_len,
        typename KernelPolicy::SizeT    max_vertices,
        typename KernelPolicy::SizeT    max_edges,
        util::CtaWorkProgress           work_progress,
        util::KernelRuntimeStats        kernel_stats)
{
    Dispatch<KernelPolicy, ProblemData, Functor>::RelaxLightEdges(
                                queue_reset,
                                queue_index,
                                label,
                                d_row_offsets,
                                d_column_indices,
                                d_scanned_edges,
                                d_done,
                                d_queue,
                                d_out,
                                problem,
                                input_queue_len,
                                output_queue_len,
                                max_vertices,
                                max_edges,
                                work_progress,
                                kernel_stats);
}

/**
 * @brief Kernel entry for computing neighbor list length for each vertex in the current frontier
 *
 * @tparam KernelPolicy Kernel policy type for partitioned edge mapping.
 * @tparam ProblemData Problem data type for partitioned edge mapping.
 * @tparam Functor Functor type for the specific problem type.
 *
 * @param[in] d_row_offset      Device pointer of SizeT to the row offsets queue
 * @param[in] d_queue           Device pointer of VertexId to the incoming frontier queue
 * @param[out] d_scanned_edges   Device pointer of scanned neighbor list queue of the current frontier
 * @param[in] num_elements      Length of the current frontier queue
 * @param[in] max_vertices      Maximum number of elements we can place into the incoming frontier
 * @param[in] max_edges         Maximum number of elements we can place into the outgoing frontier
 */
template <typename KernelPolicy, typename ProblemData, typename Functor>
__launch_bounds__ (KernelPolicy::THREADS, KernelPolicy::CTA_OCCUPANCY)
    __global__
void GetEdgeCounts(
                                typename KernelPolicy::SizeT *d_row_offsets,
                                typename KernelPolicy::VertexId *d_queue,
                                unsigned int *d_scanned_edges,
                                typename KernelPolicy::SizeT num_elements,
                                typename KernelPolicy::SizeT max_vertex,
                                typename KernelPolicy::SizeT max_edge)
{
    Dispatch<KernelPolicy, ProblemData, Functor>::GetEdgeCounts(
                                    d_row_offsets,
                                    d_queue,
                                    d_scanned_edges,
                                    num_elements,
                                    max_vertex,
                                    max_edge);
}

} //edge_map_partitioned
} //oprtr
} //gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
