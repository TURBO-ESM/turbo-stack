#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <set>

#include <hdf5.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "grid.h"

namespace turbo {

// Enum to specify the location of the field on the grid
enum class FieldGridStagger {
    Nodal,         
    CellCentered,  
    IFace,         
    JFace,         
    KFace          
};

// Helper function to convert FieldGridStagger to string. Convenient for error messages and generating field names on the fly.
inline std::string FieldGridStaggerToString(FieldGridStagger field_grid_stagger) {
    switch (field_grid_stagger) {
        case FieldGridStagger::Nodal:        return "Nodal";
        case FieldGridStagger::CellCentered: return "CellCentered";
        case FieldGridStagger::IFace:        return "IFace";
        case FieldGridStagger::JFace:        return "JFace";
        case FieldGridStagger::KFace:        return "KFace";
        default: throw std::invalid_argument("FieldGridStaggerToString Invalid FieldGridStagger specified.");
    }
}

class Field {

public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//
    using ValueType = amrex::Real;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    Field(const std::string& name, const std::shared_ptr<Grid> grid, const FieldGridStagger field_grid_stagger, const std::size_t n_component, const std::size_t n_ghost);

    // Convenience functions to check the field location
    bool IsCellCentered() const noexcept;
    bool IsXFaceCentered() const noexcept;
    bool IsYFaceCentered() const noexcept;
    bool IsZFaceCentered() const noexcept;
    bool IsNodal() const noexcept;

    // This is where the coupling between the Field and Grid classes happens. Your field knows where it is on the grid and can ask the grid for the location of a point given its indices.
    Grid::Point GetGridPoint(int i, int j, int k) const;

    // Write the field data to an HDF5 file. This will overwrite the file if it already exists.
    void WriteHDF5(const std::string filename) const;

    // Write the field data to an already open HDF5 file that you already have open.
    void WriteHDF5(const hid_t file_id) const;

    // Helpful because it automatically generates all six relational operators (<, <=, >, >=, ==, !=) based on member-wise comparison.
    // But note that comparing the data member grid ( ...which is has a type shared_ptr<Grid> ) the operators compares the pointer addresses, not the contents of the Grid objects.
    // In general don't think it would make sense to compare two fields built on different grids with the less than or greater than operators (<, >). But doing so with pointer address does work to supply a strict weak ordering, even if it is an arbitrary one, which lets us store Field in a standard ordered containers like std::set or std::map.
    auto operator<=>(const Field& other) const = default;

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//
    const std::shared_ptr<Grid> grid;
    const std::string name;
    const FieldGridStagger field_grid_stagger;
    std::shared_ptr<amrex::MultiFab> multifab;

private:

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//    

    amrex::IndexType FieldGridStaggerToAMReXIndexType(const FieldGridStagger field_location) const;

    std::shared_ptr<amrex::MultiFab> CopyMultiFabToSingleRank(const std::shared_ptr<amrex::MultiFab>& source_mf, int dest_rank) const;

};

} // namespace turbo