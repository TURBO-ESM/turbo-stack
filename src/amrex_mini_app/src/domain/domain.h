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

// For cartesian domain
#include "cartesian_grid.h"

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
    // There should be a way to get the geometry from the grid, so maybe only pass in the grid when we get that worked out.
    Domain(const std::shared_ptr<Geometry>& geometry, const std::shared_ptr<Grid>& grid);

    /**
     * @brief Virtual destructor for Domain.
     */
    virtual ~Domain() = default;

    // Accessors
    std::shared_ptr<Geometry> GetGeometry() const noexcept { return geometry_; }
    std::shared_ptr<Grid> GetGrid() const noexcept { return grid_; }
    std::shared_ptr<FieldContainer> GetFields() const noexcept { return fields_; }

    /**
     * @brief Write the domain data to an HDF5 file.
     * @param filename Name of the HDF5 file to write.
     */
    void WriteHDF5(const std::string& filename) const ;

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//

protected:
    /**
     * @brief Shared pointer to the geometry associated with the domain.
     */
    const std::shared_ptr<Geometry> geometry_;

    /**
     * @brief Shared pointer to the grid associated with the domain.
     */
    const std::shared_ptr<Grid> grid_;

    /**
     * @brief Shared pointer to the field container holding the domain's fields.
     */
    const std::shared_ptr<FieldContainer> fields_;

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

};

class CartesianDomain : public Domain {

public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    CartesianDomain(double x_min, double x_max,
           double y_min, double y_max,
           double z_min, double z_max,
           std::size_t n_cell_x,
           std::size_t n_cell_y,
           std::size_t n_cell_z);

    // Accessors
    std::shared_ptr<CartesianGeometry> GetGeometry() const noexcept { 
        return std::static_pointer_cast<CartesianGeometry>(geometry_);
    }

    std::shared_ptr<CartesianGrid> GetGrid() const noexcept { 
        return std::static_pointer_cast<CartesianGrid>(grid_);
    }

    std::shared_ptr<FieldContainer> GetFields() const noexcept { return fields_; }

    //// Convenience functions to initialize all the scalar and vector MultiFabs given a function 
    //template <typename Func>
    //void InitializeScalarMultiFabs(Func initialization_function);

    //template <typename Func>
    //void InitializeVectorMultiFabs(Func initialization_function);

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//


private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

};

//template <typename Func>
//void Domain::InitializeScalarMultiFabs(Func initializer_function) {
//    static_assert(
//        std::is_invocable_r_v<double, Func, double, double, double>,
//        "initializer_function must be callable as double(double, double, double). The arguments are the x, y, and z coordinates of the point and the return value is the function evaluated at that point."
//    );
//
//    for (const auto& field : *field_container_) {
//        if (field->multifab->nComp() == 1) {
//            for (amrex::MFIter mfi(*field->multifab); mfi.isValid(); ++mfi) {
//                const amrex::Array4<amrex::Real>& array = field->multifab->array(mfi);
//                amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
//                    const Grid::Point location = field->GetGridPoint(i, j, k); 
//                    array(i, j, k) = initializer_function(location.x, location.y, location.z);
//                });
//            }
//        }
//    }
//}
//
//template <typename Func>
//void Domain::InitializeVectorMultiFabs(Func initializer_function) {
//    static_assert(
//        std::is_invocable_r_v<std::array<double, 3>, Func, double, double, double>,
//        "initializer_function must be callable as std::array<double, 3>(double, double, double). The arguments are the x, y, and z coordinates of the point and the return value is an array of 3 doubles representing the vector function evaluated at that point."
//    );
//
//    for (const auto& field : *field_container_) {
//        if (field->multifab->nComp() == 3) {
//            for (amrex::MFIter mfi(*field->multifab); mfi.isValid(); ++mfi) {
//                const amrex::Array4<amrex::Real>& array = field->multifab->array(mfi);
//                amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
//                    const Grid::Point location = field->GetGridPoint(i, j, k);
//                    std::array<double, 3> initial_vector = initializer_function(location.x, location.y, location.z);
//                    array(i, j, k, 0) = initial_vector[0];
//                    array(i, j, k, 1) = initial_vector[1];
//                    array(i, j, k, 2) = initial_vector[2];
//                });
//            }
//        }
//    }
//}

} // namespace turbo