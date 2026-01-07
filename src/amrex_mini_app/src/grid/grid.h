#pragma once

#include <hdf5.h>

#include <cstddef>
#include <string>
#include <memory>

#include "geometry.h"

namespace turbo
{

/**
 * @brief Abstract base class for discretized geometry grids.
 * Assumes that the grid is structured, 3D, and indexed by (i,j,k).
 *
 * Provides an interface for grid operations. Does things like get cell and node counts,
 * location queries, validity checks, and HDF5 output.
 */
class Grid
{
   public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//
    /**
     * @brief Type alias for grid indices.
     *
     * Note: We may want to change this type alias later to support negative
     * indices for ghost cells or periodic boundaries in some implementations.
     */
    using Index = std::size_t;
    // Thinking ahead to AMReX IntVect actually uses int internally for this type of indexing.
    // Because an index can be negative for ghost cells on the boundaries of the domain, etc.
    // For now this class is using std::size_t and assuming we do the checks/conversions when needed for potential
    // negative indices for wrapping around the domain boundaries (e.g., for periodic boundary conditions or ghost
    // cells).

    struct Point
    {
        double x; /**< X coordinate */
        double y; /**< Y coordinate */
        double z; /**< Z coordinate */

        /**
         * @brief Equality operator for Point.
         */
        bool operator==(const Point&) const = default;

        /**
         * @brief Addition operator for Point.
         * @param other Point to add
         * @return Sum of two points
         */
        Point operator+(const Point& other) const noexcept { return {x + other.x, y + other.y, z + other.z}; }
    };

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    /**
     * @brief Construct a Grid with the given geometry.
     * @param geometry Shared pointer to Geometry object
     */
    Grid(const std::shared_ptr<Geometry>& geometry) : geometry_(geometry)
    {
        if (!geometry_)
        {
            throw std::invalid_argument("Null geometry pointer passed to Grid constructor.");
        }
    }

    /**
     * @brief Get the geometry associated with the grid.
     * @return Shared pointer to Geometry object
     */
    std::shared_ptr<Geometry> GetGeometry() const noexcept { return geometry_; }
    
    /**
     * @brief Virtual destructor for Grid.
     */
    virtual ~Grid() = default;

    /**
     * @brief Get the total number of cells in the grid.
     * @return Number of cells
     */
    virtual std::size_t NCell() const noexcept = 0;

    /**
     * @brief Get the number of cells in the I index direction.
     * @return Number of cells in I index direction
     */
    virtual std::size_t NCellI() const noexcept = 0;

    /**
     * @brief Get the number of cells in the J index direction.
     * @return Number of cells in J index direction
     */
    virtual std::size_t NCellJ() const noexcept = 0;

    /**
     * @brief Get the number of cells in the K index direction.
     * @return Number of cells in K index direction
     */
    virtual std::size_t NCellK() const noexcept = 0;

    /**
     * @brief Get the total number of nodes in the grid.
     * @return Number of nodes
     */
    virtual std::size_t NNode() const noexcept = 0;

    /**
     * @brief Get the number of nodes in the I index direction.
     * @return Number of nodes in I index direction
     */
    virtual std::size_t NNodeI() const noexcept = 0;

    /**
     * @brief Get the number of nodes in the J index direction.
     * @return Number of nodes in J index direction
     */
    virtual std::size_t NNodeJ() const noexcept = 0;

    /**
     * @brief Get the number of nodes in the K index direction.
     * @return Number of nodes in K index direction
     */
    virtual std::size_t NNodeK() const noexcept = 0;

    /**
     * @brief Get the location of a node.
     * @param i Node I index
     * @param j Node J index
     * @param k Node K index
     * @return Grid point location of the node
     */
    virtual Point Node(const Index i, const Index j, const Index k) const = 0;

    /**
     * @brief Get the location of a cell center.
     * @param i Cell I index
     * @param j Cell J index
     * @param k Cell K index
     * @return Grid point location of the cell center
     */
    virtual Point CellCenter(const Index i, const Index j, const Index k) const = 0;

    /**
     * @brief Get the location of the I-face center.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return Grid point location of the I-face center
     */
    virtual Point IFace(const Index i, const Index j, const Index k) const = 0;

    /**
     * @brief Get the location of the J-face center.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return Grid point location of the J-face center
     */
    virtual Point JFace(const Index i, const Index j, const Index k) const = 0;

    /**
     * @brief Get the location of the K-face center.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return Grid point location of the K-face center
     */
    virtual Point KFace(const Index i, const Index j, const Index k) const = 0;

    /**
     * @brief Check if the given node indices are valid for the grid.
     * @param i Node I index
     * @param j Node J index
     * @param k Node K index
     * @return True if valid, false otherwise
     */
    virtual bool ValidNode(const Index i, const Index j, const Index k) const noexcept = 0;

    /**
     * @brief Check if the given cell indices are valid for the grid.
     * @param i Cell I index
     * @param j Cell J index
     * @param k Cell K index
     * @return True if valid, false otherwise
     */
    virtual bool ValidCell(const Index i, const Index j, const Index k) const noexcept = 0;

    /**
     * @brief Check if the given I-face indices are valid for the grid.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return True if valid, false otherwise
     */
    virtual bool ValidIFace(const Index i, const Index j, const Index k) const noexcept = 0;

    /**
     * @brief Check if the given J-face indices are valid for the grid.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return True if valid, false otherwise
     */
    virtual bool ValidJFace(const Index i, const Index j, const Index k) const noexcept = 0;

    /**
     * @brief Check if the given K-face indices are valid for the grid.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return True if valid, false otherwise
     */
    virtual bool ValidKFace(const Index i, const Index j, const Index k) const noexcept = 0;

    /**
     * @brief Write grid data to an HDF5 file by filename. Overwrites the file if it already exists.
     * @param filename Name of the HDF5 file
     */
    virtual void WriteHDF5(const std::string& filename) const = 0;

    /**
     * @brief Write grid data to an HDF5 file by file ID.
     * @param file_id HDF5 file identifier
     */
    virtual void WriteHDF5(const hid_t file_id) const = 0;


   protected:
    //-----------------------------------------------------------------------//
    // Protected Member Functions
    //-----------------------------------------------------------------------//
    const std::shared_ptr<Geometry> geometry_;

};

}  // namespace turbo
