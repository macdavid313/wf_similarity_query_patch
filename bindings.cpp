/*
 * File: bindings.cpp
 * Created Date: Thursday, 5th November 2020 10:32:07 am
 * Author: Tianyu Gu (gty@franz.com)
 */

#include "annoylib.h"
#include "kissrandom.h"
#include <exception>

#if defined(_MSC_VER) && _MSC_VER == 1500
typedef signed __int32 int32_t;
#else
#include <stdint.h>
#endif

#if _WIN32
#define DLLEXPORT __declspec(dllexport)
#else
#define DLLEXPORT
#endif

#define EXTERN_C extern "C"

#ifdef ANNOYLIB_MULTITHREADED_BUILD
typedef AnnoyIndexMultiThreadedBuildPolicy AnnoyIndexThreadedBuildPolicy;
#else
typedef AnnoyIndexSingleThreadedBuildPolicy AnnoyIndexThreadedBuildPolicy;
#endif

template class AnnoyIndexInterface<int32_t, float>;

class HammingWrapper : public AnnoyIndexInterface<int32_t, float>
{
    // Wrapper class for Hamming distance, using composition.
    // This translates binary (float) vectors into packed uint64_t vectors.
    // This is questionable from a performance point of view. Should reconsider this solution.
private:
    int32_t _f_external, _f_internal;
    AnnoyIndex<int32_t, uint64_t, Hamming, Kiss64Random, AnnoyIndexThreadedBuildPolicy> _index;
    void _pack(const float *src, uint64_t *dst) const
    {
        for (int32_t i = 0; i < _f_internal; i++)
        {
            dst[i] = 0;
            for (int32_t j = 0; j < 64 && i * 64 + j < _f_external; j++)
            {
                dst[i] |= (uint64_t)(src[i * 64 + j] > 0.5) << j;
            }
        }
    };
    void _unpack(const uint64_t *src, float *dst) const
    {
        for (int32_t i = 0; i < _f_external; i++)
        {
            dst[i] = (src[i / 64] >> (i % 64)) & 1;
        }
    };

public:
    HammingWrapper(int f) : _f_external(f), _f_internal((f + 63) / 64), _index((f + 63) / 64){};
    bool add_item(int32_t item, const float *w, char **error)
    {
        vector<uint64_t> w_internal(_f_internal, 0);
        _pack(w, &w_internal[0]);
        return _index.add_item(item, &w_internal[0], error);
    };
    bool build(int q, int n_threads, char **error) { return _index.build(q, n_threads, error); };
    bool unbuild(char **error) { return _index.unbuild(error); };
    bool save(const char *filename, bool prefault, char **error) { return _index.save(filename, prefault, error); };
    void unload() { _index.unload(); };
    bool load(const char *filename, bool prefault, char **error) { return _index.load(filename, prefault, error); };
    float get_distance(int32_t i, int32_t j) const { return _index.get_distance(i, j); };
    void get_nns_by_item(int32_t item, size_t n, int search_k, vector<int32_t> *result, vector<float> *distances) const
    {
        if (distances)
        {
            vector<uint64_t> distances_internal;
            _index.get_nns_by_item(item, n, search_k, result, &distances_internal);
            distances->insert(distances->begin(), distances_internal.begin(), distances_internal.end());
        }
        else
        {
            _index.get_nns_by_item(item, n, search_k, result, NULL);
        }
    };
    void get_nns_by_vector(const float *w, size_t n, int search_k, vector<int32_t> *result, vector<float> *distances) const
    {
        vector<uint64_t> w_internal(_f_internal, 0);
        _pack(w, &w_internal[0]);
        if (distances)
        {
            vector<uint64_t> distances_internal;
            _index.get_nns_by_vector(&w_internal[0], n, search_k, result, &distances_internal);
            distances->insert(distances->begin(), distances_internal.begin(), distances_internal.end());
        }
        else
        {
            _index.get_nns_by_vector(&w_internal[0], n, search_k, result, NULL);
        }
    };
    int32_t get_n_items() const { return _index.get_n_items(); };
    int32_t get_n_trees() const { return _index.get_n_trees(); };
    void verbose(bool v) { _index.verbose(v); };
    void get_item(int32_t item, float *v) const
    {
        vector<uint64_t> v_internal(_f_internal, 0);
        _index.get_item(item, &v_internal[0]);
        _unpack(&v_internal[0], v);
    };
    void set_seed(int q) { _index.set_seed(q); };
    bool on_disk_build(const char *filename, char **error) { return _index.on_disk_build(filename, error); };
};

typedef struct
{
    AnnoyIndexInterface<int32_t, float> *ptr;
} AnnoyIndexWrapper;

EXTERN_C AnnoyIndexWrapper *annoy_alloc(int dim, const char *metric)
{
    AnnoyIndexWrapper *self = (AnnoyIndexWrapper *)malloc(sizeof(AnnoyIndexWrapper));
    if (!strcmp(metric, "angular"))
    {
        self->ptr = new AnnoyIndex<int32_t, float, Angular, Kiss64Random, AnnoyIndexThreadedBuildPolicy>(dim);
    }
    else if (!strcmp(metric, "euclidean"))
    {
        self->ptr = new AnnoyIndex<int32_t, float, Euclidean, Kiss64Random, AnnoyIndexThreadedBuildPolicy>(dim);
    }
    else if (!strcmp(metric, "manhattan"))
    {
        self->ptr = new AnnoyIndex<int32_t, float, Manhattan, Kiss64Random, AnnoyIndexThreadedBuildPolicy>(dim);
    }
    else if (!strcmp(metric, "hamming"))
    {
        self->ptr = new HammingWrapper(dim);
    }
    else if (!strcmp(metric, "dot"))
    {
        self->ptr = new AnnoyIndex<int32_t, float, DotProduct, Kiss64Random, AnnoyIndexThreadedBuildPolicy>(dim);
    }
    else
    {
        return NULL;
    }
    return self;
}

EXTERN_C void annoy_dealloc(AnnoyIndexWrapper *index)
{
    delete index->ptr;
    free(index);
}

EXTERN_C int annoy_load(AnnoyIndexWrapper *index, const char *filename, bool prefault)
{
    if (!index->ptr)
        return 0;
    if (!index->ptr->load(filename, prefault, NULL))
    {
        return 0;
    }
    return 1;
}

EXTERN_C int32_t annoy_get_n_items(AnnoyIndexWrapper *index)
{
    if (index->ptr)
    {
        return index->ptr->get_n_items();
    }
    return -1;
}

EXTERN_C int32_t annoy_get_n_trees(AnnoyIndexWrapper *index)
{
    if (index->ptr)
    {
        return index->ptr->get_n_trees();
    }
    return -1;
}

EXTERN_C void annoy_get_item(AnnoyIndexWrapper *index, int32_t item, float *v)
{
    if (index->ptr)
    {
        index->ptr->get_item(item, v);
    }
}

EXTERN_C void annoy_get_nns_by_item(AnnoyIndexWrapper *index, int32_t item, size_t n, int search_k, int32_t *result, float *distances)
{
    if (index->ptr)
    {
        vector<int32_t> tmp_result;
        vector<float> tmp_distances;
        index->ptr->get_nns_by_item(item, n, search_k, &tmp_result, &tmp_distances);
        for (int i = 0; i < tmp_result.size(); i++)
        {
            result[i] = tmp_result[i];
            distances[i] = tmp_distances[i];
        }
    }
}
