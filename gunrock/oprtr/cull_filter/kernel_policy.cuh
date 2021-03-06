// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * kernel_policy.cuh
 *
 * @brief Kernel configuration policy for cull filter
 */

#pragma once

#include <gunrock/util/basic_utils.h>
#include <gunrock/util/cuda_properties.cuh>
#include <gunrock/util/cta_work_distribution.cuh>
#include <gunrock/util/srts_grid.cuh>
#include <gunrock/util/srts_details.cuh>
#include <gunrock/util/io/modified_load.cuh>
#include <gunrock/util/io/modified_store.cuh>

namespace gunrock {
namespace oprtr {
namespace cull_filter {

template <
    typename _Problem,

    // Machine parameters
    int _CUDA_ARCH,
    //bool _INSTRUMENT,
    // Behavioral control parameters
    int _SATURATION_QUIT,
    bool _DEQUEUE_PROBLEM_SIZE,

    // Tunable parameters
    int _MAX_CTA_OCCUPANCY,
    int _LOG_THREADS,
    int _LOG_LOAD_VEC_SIZE,
    int _LOG_LOADS_PER_TILE,
    int _LOG_RAKING_THREADS,
    int _END_BITMASK_CULL,
    int _LOG_SCHEDULE_GRANULARITY,
    int _MODE>
struct KernelPolicy
{
    //---------------------------------------------------------------------
    // Constants and typedefs
    //---------------------------------------------------------------------

    typedef _Problem                    Problem;
    typedef typename Problem::VertexId  VertexId;
    typedef typename Problem::SizeT     SizeT;
    typedef typename Problem::Value     Value;

    enum {
        MODE                            = _MODE,
        CUDA_ARCH                       = _CUDA_ARCH,
        SATURATION_QUIT                 = _SATURATION_QUIT,
        DEQUEUE_PROBLEM_SIZE            = _DEQUEUE_PROBLEM_SIZE,

        //INSTRUMENT                      = _INSTRUMENT,

        LOG_THREADS                     = _LOG_THREADS,
        THREADS                         = 1 << LOG_THREADS,

        LOG_LOAD_VEC_SIZE               = _LOG_LOAD_VEC_SIZE,
        LOAD_VEC_SIZE                   = 1 << LOG_LOAD_VEC_SIZE,

        LOG_LOADS_PER_TILE              = _LOG_LOADS_PER_TILE,
        LOADS_PER_TILE                  = 1 << LOG_LOADS_PER_TILE,

        LOG_RAKING_THREADS              = _LOG_RAKING_THREADS,
        RAKING_THREADS                  = 1 << LOG_RAKING_THREADS,

        LOG_WARPS                       = LOG_THREADS - GR_LOG_WARP_THREADS(CUDA_ARCH),
        WARPS                           = 1 << LOG_WARPS,

        LOG_TILE_ELEMENTS_PER_THREAD    = LOG_LOAD_VEC_SIZE + LOG_LOADS_PER_TILE,
        TILE_ELEMENTS_PER_THREAD        = 1 << LOG_TILE_ELEMENTS_PER_THREAD,

        LOG_TILE_ELEMENTS               = LOG_TILE_ELEMENTS_PER_THREAD + LOG_THREADS,
        TILE_ELEMENTS                   = 1 << LOG_TILE_ELEMENTS,

        LOG_SCHEDULE_GRANULARITY        = _LOG_SCHEDULE_GRANULARITY,
        SCHEDULE_GRANULARITY            = 1 << LOG_SCHEDULE_GRANULARITY,

        END_BITMASK_CULL                = _END_BITMASK_CULL,
    };

    //Prefix sum raking grid for contraction allocations
    typedef util::RakingGrid<
        CUDA_ARCH,
        SizeT,                          // Partial type (valid counts)
        LOG_THREADS,                    // Depositing threads (the CTA size)
        LOG_LOADS_PER_TILE,             // Lanes (the number of loads)
        LOG_RAKING_THREADS,             // Raking threads
        true>                           // There are prefix dependences between lanes
            RakingGrid;

    // Operational details type for raking grid type
    typedef util::RakingDetails<RakingGrid> RakingDetails;

    /**
     * @brief Shared memory storage type for the CTA
     */
    struct SmemStorage
    {

        enum {
            WARP_HASH_ELEMENTS          = 128,          // Collision hash table size (per warp)
            WARP_HASH_MASK              = WARP_HASH_ELEMENTS -1,
        };

        // Persistent shared state for the CTA
        struct State {

            // Shared work-processing limits
            util::CtaWorkDistribution<SizeT>    work_decomposition;

            // Storage for scanning local ranks
            SizeT                               warpscan[2][GR_WARP_THREADS(CUDA_ARCH)];

            // General pool for prefix sum
            union {
                SizeT                               raking_elements[RakingGrid::TOTAL_RAKING_ELEMENTS];
                /*volatile*/ VertexId                   vid_hashtable[WARPS][WARP_HASH_ELEMENTS];
            };

        } state;


        enum {
            // Amount of storage we can use for hashing scratch space under target occupancy
            FULL_OCCUPANCY_BYTES                = (GR_SMEM_BYTES(CUDA_ARCH) / _MAX_CTA_OCCUPANCY)
                                                    - sizeof(State)
                                                    - 128,                                              // Fudge-factor to guarantee occupancy
            HISTORY_HASH_ELEMENTS               = FULL_OCCUPANCY_BYTES / sizeof(VertexId), // 256,
            //HISTORY_HASH_MASK                   = HISTORY_HASH_ELEMENTS -1,

        };

        // Fill the remainder of smem with a history-based hash-cache of seen vertex-ids
        /*volatile*/ VertexId                      history[HISTORY_HASH_ELEMENTS];

    };

    enum {
        THREAD_OCCUPANCY    = GR_SM_THREADS(CUDA_ARCH) >> LOG_THREADS,
        SMEM_OCCUPANCY      = GR_SMEM_BYTES(CUDA_ARCH) / sizeof(SmemStorage),
        CTA_OCCUPANCY       = GR_MIN(_MAX_CTA_OCCUPANCY, GR_MIN(GR_SM_CTAS(CUDA_ARCH), GR_MIN(THREAD_OCCUPANCY, SMEM_OCCUPANCY))),
        VALID               = (CTA_OCCUPANCY > 0),
	    ELEMENT_ID_MASK	    = ~(1ULL<<(sizeof(VertexId)*8-2)),								// Bitmask for masking off the upper control bits in element identifier
    };

}; // end of kernelPolicy

} // namespace cull_filter
} // namespace oprtr
} // namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
