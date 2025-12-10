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

#include "geometry.h"
#include "grid.h"
#include "field.h"
#include "field_container.h"

namespace turbo {

class Domain {

public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    //Domain(double x_min, double x_max,
    //       double y_min, double y_max,
    //       double z_min, double z_max,
    //       std::size_t n_cell_x,
    //       std::size_t n_cell_y,
    //       std::size_t n_cell_z);

    Domain(const std::shared_ptr<Grid>& grid);

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
    //const std::shared_ptr<Geometry> geometry_; // Geometry object describing the domain. Probably want a way to add a way to store this later?
    const std::shared_ptr<Grid> grid_;
    const std::shared_ptr<FieldContainer> field_container_;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

};

template <typename Func>
void Domain::InitializeScalarMultiFabs(Func initializer_function) {
    static_assert(
        std::is_invocable_r_v<double, Func, double, double, double>,
        "initializer_function must be callable as double(double, double, double). The arguments are the x, y, and z coordinates of the point and the return value is the function evaluated at that point."
    );

    for (const auto& field : *field_container_) {
        if (field->multifab->nComp() == 1) {
            for (amrex::MFIter mfi(*field->multifab); mfi.isValid(); ++mfi) {
                const amrex::Array4<amrex::Real>& array = field->multifab->array(mfi);
                amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
                    const Grid::Point location = field->GetGridPoint(i, j, k); 
                    array(i, j, k) = initializer_function(location.x, location.y, location.z);
                });
            }
        }
    }
}

template <typename Func>
void Domain::InitializeVectorMultiFabs(Func initializer_function) {
    static_assert(
        std::is_invocable_r_v<std::array<double, 3>, Func, double, double, double>,
        "initializer_function must be callable as std::array<double, 3>(double, double, double). The arguments are the x, y, and z coordinates of the point and the return value is an array of 3 doubles representing the vector function evaluated at that point."
    );

    for (const auto& field : *field_container_) {
        if (field->multifab->nComp() == 3) {
            for (amrex::MFIter mfi(*field->multifab); mfi.isValid(); ++mfi) {
                const amrex::Array4<amrex::Real>& array = field->multifab->array(mfi);
                amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
                    const Grid::Point location = field->GetGridPoint(i, j, k);
                    std::array<double, 3> initial_vector = initializer_function(location.x, location.y, location.z);
                    array(i, j, k, 0) = initial_vector[0];
                    array(i, j, k, 1) = initial_vector[1];
                    array(i, j, k, 2) = initial_vector[2];
                });
            }
        }
    }
}

} // namespace turbo