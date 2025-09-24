#pragma once

#include <cstddef>
#include <functional>
#include <type_traits>
#include <memory>
#include <unordered_set>
#include <string>

#include <hdf5.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "grid.h"
#include "field.h"

namespace turbo {

class TripolarGrid {

public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//
    using ValueType = amrex::Real;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    //TripolarGrid(const std::size_t n_cell_x, const std::size_t n_cell_y, const std::size_t n_cell_z);
    TripolarGrid(const std::shared_ptr<Grid>& grid);

    // Function to get the location of a point in the grid for a given MultiFab and index i,j,k
    Grid::Point GetLocation(const std::shared_ptr<amrex::MultiFab>& mf, int i, int j, int k) const;

    // Convenience functions to initialize all the scalar and vector MultiFabs given a function 
    template <typename Func>
    void InitializeScalarMultiFabs(Func initialization_function);

    template <typename Func>
    void InitializeVectorMultiFabs(Func initialization_function);

    // Output functions
    void WriteHDF5(const std::string& filename) const;

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//

    // A scalar and a vector MultiFab at each location in the grid.
    std::shared_ptr<amrex::MultiFab> cell_scalar;
    std::shared_ptr<amrex::MultiFab> cell_vector;

    std::shared_ptr<amrex::MultiFab> x_face_scalar;
    std::shared_ptr<amrex::MultiFab> x_face_vector;

    std::shared_ptr<amrex::MultiFab> y_face_scalar;
    std::shared_ptr<amrex::MultiFab> y_face_vector;

    std::shared_ptr<amrex::MultiFab> z_face_scalar;
    std::shared_ptr<amrex::MultiFab> z_face_vector;

    std::shared_ptr<amrex::MultiFab> node_scalar;
    std::shared_ptr<amrex::MultiFab> node_vector;

    // Collections of MultiFabs for easier testing
    std::unordered_set<std::shared_ptr<amrex::MultiFab>> all_multifabs;

    std::unordered_set<std::shared_ptr<amrex::MultiFab>> scalar_multifabs;
    std::unordered_set<std::shared_ptr<amrex::MultiFab>> vector_multifabs;

    std::unordered_set<std::shared_ptr<amrex::MultiFab>> cell_multifabs;
    std::unordered_set<std::shared_ptr<amrex::MultiFab>> x_face_multifabs;
    std::unordered_set<std::shared_ptr<amrex::MultiFab>> y_face_multifabs;
    std::unordered_set<std::shared_ptr<amrex::MultiFab>> z_face_multifabs;
    std::unordered_set<std::shared_ptr<amrex::MultiFab>> node_multifabs;

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    const std::shared_ptr<Grid> grid_;
    const std::shared_ptr<FieldContainer> field_container_;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

    bool IsCellCentered(const std::shared_ptr<amrex::MultiFab>& mf) const noexcept{
        return mf->is_cell_centered();
    }

    bool IsXFaceCentered(const std::shared_ptr<amrex::MultiFab>& mf) const noexcept {
        return (mf->is_nodal(0) == true  && mf->is_nodal(1) == false && mf->is_nodal(2) == false);
    }

    bool IsYFaceCentered(const std::shared_ptr<amrex::MultiFab>& mf) const noexcept{
        return (mf->is_nodal(0) == false && mf->is_nodal(1) == true  && mf->is_nodal(2) == false);
    }

    bool IsZFaceCentered(const std::shared_ptr<amrex::MultiFab>& mf) const noexcept {
        return (mf->is_nodal(0) == false && mf->is_nodal(1) == false && mf->is_nodal(2) == true);
    }

    bool IsNodal(const std::shared_ptr<amrex::MultiFab>& mf) const noexcept {
        return mf->is_nodal();
    }

    // Utility to copy a MultiFab to a single rank 
    // Returns a pointer to a new MultiFab that contains all the data from the original MultiFab but now on a single box and rank.
    std::shared_ptr<amrex::MultiFab> CopyMultiFabToSingleRank(const std::shared_ptr<amrex::MultiFab>& src_mf, int dest_rank = 0) const;

    void WriteMultiFabsToHDF5(const hid_t file_id) const;

    void WriteGeometryToHDF5(const hid_t file_id) const;

    //void WriteXDMF(const std::string& h5_filename,
    //               const std::string& xdmf_filename) const;

};

template <typename Func>
void TripolarGrid::InitializeScalarMultiFabs(Func initializer_function) {
    static_assert(
        std::is_invocable_r_v<double, Func, double, double, double>,
        "initializer_function must be callable as double(double, double, double). The arguments are the x, y, and z coordinates of the point and the return value is the function evaluated at that point."
    );

    for (const std::shared_ptr<amrex::MultiFab>& mf : scalar_multifabs) {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
            const amrex::Array4<amrex::Real>& array = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
                const Grid::Point location = GetLocation(mf, i, j, k);
                array(i, j, k) = initializer_function(location.x, location.y, location.z);
            });
        }
    }
}

template <typename Func>
void TripolarGrid::InitializeVectorMultiFabs(Func initializer_function) {
    static_assert(
        std::is_invocable_r_v<std::array<double, 3>, Func, double, double, double>,
        "initializer_function must be callable as std::array<double, 3>(double, double, double). The arguments are the x, y, and z coordinates of the point and the return value is an array of 3 doubles representing the vector function evaluated at that point."
    );

    for (const std::shared_ptr<amrex::MultiFab>& mf : vector_multifabs) {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
            const amrex::Array4<amrex::Real>& array = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
                const Grid::Point location = GetLocation(mf, i, j, k);
                std::array<double, 3> initial_vector = initializer_function(location.x, location.y, location.z);
                array(i, j, k, 0) = initial_vector[0];
                array(i, j, k, 1) = initial_vector[1];
                array(i, j, k, 2) = initial_vector[2];
            });
        }
    }
}

} // namespace turbo