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

/**
 * @enum FieldGridStagger
 * @brief Specifies the location of the field on the grid.
 */
enum class FieldGridStagger {
    Nodal,         /**< Field is defined at grid nodes. */
    CellCentered,  /**< Field is defined at cell centers. */
    IFace,         /**< Field is defined at I (x) faces. */
    JFace,         /**< Field is defined at J (y) faces. */
    KFace          /**< Field is defined at K (z) faces. */
};


/**
 * @brief Convert a FieldGridStagger enum value to a string. Useful for debugging and logging.
 * @param field_grid_stagger The FieldGridStagger value to convert.
 * @return String representation of the field grid stagger.
 * @throws std::invalid_argument if the value is invalid.
 */
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


/**
 * @class Field
 * @brief Represents a physical field defined on a computational grid.
 *
 * The Field class manages data storage, grid location, and I/O for a field variable.
 * It supports different grid staggers, HDF5 output, and AMReX MultiFab integration.
 */
class Field {

public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//

    /**
     * @brief Value type for field data (AMReX real type).
     */
    using ValueType = amrex::Real;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    /**
     * @brief Construct a new Field object.
     * @param name Name of the field.
     * @param grid Shared pointer to the grid on which the field is defined.
     * @param field_grid_stagger Location of the field on the grid.
     * @param n_component Number of components (e.g., 1 for a scalar field).
     * @param n_ghost Number of ghost cells.
     */
    Field(const std::string& name, const std::shared_ptr<Grid> grid, const FieldGridStagger field_grid_stagger, const std::size_t n_component, const std::size_t n_ghost);

    /**
     * @brief Check if the field is cell-centered.
     * @return true if cell-centered, false otherwise.
     */
    bool IsCellCentered() const noexcept;

    /**
     * @brief Check if the field is x-face centered.
     * @return true if x-face centered, false otherwise.
     */
    bool IsXFaceCentered() const noexcept;

    /**
     * @brief Check if the field is y-face centered.
     * @return true if y-face centered, false otherwise.
     */
    bool IsYFaceCentered() const noexcept;

    /**
     * @brief Check if the field is z-face centered.
     * @return true if z-face centered, false otherwise.
     */
    bool IsZFaceCentered() const noexcept;

    /**
     * @brief Check if the field is nodal.
     * @return true if nodal, false otherwise.
     */
    bool IsNodal() const noexcept;

    /**
     * @brief Get the physical location of a grid point for this field. 
     *        This is where the coupling between the Field and Grid classes happens.
     *        The field knows where it is on the grid and can ask the grid for the location of a point given its indices.
     * @param i Index in the x-direction.
     * @param j Index in the y-direction.
     * @param k Index in the z-direction.
     * @return Grid::Point representing the physical location.
     */
    Grid::Point GetGridPoint(int i, int j, int k) const;

    /**
     * @brief Write the field data to an HDF5 file (overwrites file if exists).
     * @param filename Name of the HDF5 file to write.
     */
    void WriteHDF5(const std::string filename) const;

    /**
     * @brief Write the field data to an already open HDF5 file.
     * @param file_id HDF5 file identifier.
     */
    void WriteHDF5(const hid_t file_id) const;

    /**
     * @brief Default comparison operators for Field (pointer-based for grid).
     *
     * Note: Comparison is based on pointer addresses for grid, not contents.
     * This allows storage in ordered containers (e.g., std::set).
     */
    auto operator<=>(const Field& other) const = default;

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//

    /**
     * @brief Shared pointer to the grid on which the field is defined.
     */
    const std::shared_ptr<Grid> grid;

    /**
     * @brief Name of the field.
     */
    const std::string name;

    /**
     * @brief Location of the field on the grid.
     */
    const FieldGridStagger field_grid_stagger;

    /**
     * @brief AMReX MultiFab storing the field data.
     */
    std::shared_ptr<amrex::MultiFab> multifab;

private:

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//    

    /**
     * @brief Convert FieldGridStagger to AMReX IndexType.
     * @param field_location Field location enum.
     * @return Corresponding AMReX IndexType.
     */
    amrex::IndexType FieldGridStaggerToAMReXIndexType(const FieldGridStagger field_location) const;

    /**
     * @brief Copy a MultiFab to a single MPI rank.
     * @param source_mf Source MultiFab.
     * @param dest_rank Destination MPI rank.
     * @return Shared pointer to the copied MultiFab.
     */
    std::shared_ptr<amrex::MultiFab> CopyMultiFabToSingleRank(const std::shared_ptr<amrex::MultiFab>& source_mf, int dest_rank) const;

};

} // namespace turbo