#pragma once

#include <hdf5.h>

#include <cstddef>
#include <memory>

#include "cartesian_geometry.h"
#include "grid.h"

namespace turbo
{
/**
 * @brief Cartesian grid implementation for discretized geometry.
 *
 * Extends the Grid interface for Cartesian domains, providing convenience functions
 * for X, Y, Z notation and face locations. Inherited methods are documented in the parent class Grid.
 */
class CartesianGrid : public Grid
{
   public:
    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//
    /**
     * @brief Construct a CartesianGrid with the given geometry and cell counts.
     * @param geometry Shared pointer to CartesianGeometry object
     * @param n_cell_x Number of cells in X direction
     * @param n_cell_y Number of cells in Y direction
     * @param n_cell_z Number of cells in Z direction
     */
    CartesianGrid(const std::shared_ptr<CartesianGeometry>& geometry, std::size_t n_cell_x, std::size_t n_cell_y,
                  std::size_t n_cell_z);

    std::size_t NCell() const noexcept override;
    std::size_t NCellI() const noexcept override;
    std::size_t NCellJ() const noexcept override;
    std::size_t NCellK() const noexcept override;

    std::size_t NNode() const noexcept override;
    std::size_t NNodeI() const noexcept override;
    std::size_t NNodeJ() const noexcept override;
    std::size_t NNodeK() const noexcept override;

    Grid::Point Node(const Index i, const Index j, const Index k) const override;
    Grid::Point CellCenter(const Index i, const Index j, const Index k) const override;
    Grid::Point IFace(const Index i, const Index j, const Index k) const override;
    Grid::Point JFace(const Index i, const Index j, const Index k) const override;
    Grid::Point KFace(const Index i, const Index j, const Index k) const override;

    bool ValidNode(const Index i, const Index j, const Index k) const noexcept override;
    bool ValidCell(const Index i, const Index j, const Index k) const noexcept override;
    bool ValidIFace(const Index i, const Index j, const Index k) const noexcept override;
    bool ValidJFace(const Index i, const Index j, const Index k) const noexcept override;
    bool ValidKFace(const Index i, const Index j, const Index k) const noexcept override;

    void WriteHDF5(const std::string& filename) const override;
    void WriteHDF5(const hid_t file_id) const override;

    /**
     * @brief Get the number of nodes in the X direction.
     * @return Number of nodes in X direction
     */
    std::size_t NNodeX() const noexcept;

    /**
     * @brief Get the number of nodes in the Y direction.
     * @return Number of nodes in Y direction
     */
    std::size_t NNodeY() const noexcept;

    /**
     * @brief Get the number of nodes in the Z direction.
     * @return Number of nodes in the Z direction
     */
    std::size_t NNodeZ() const noexcept;

    /**
     * @brief Get the number of cells in the X direction.
     * @return Number of cells in X direction
     */
    std::size_t NCellX() const noexcept;

    /**
     * @brief Get the number of cells in the Y direction.
     * @return Number of cells in Y direction
     */
    std::size_t NCellY() const noexcept;

    /**
     * @brief Get the number of cells in the Z direction.
     * @return Number of cells in Z direction
     */
    std::size_t NCellZ() const noexcept;

    /**
     * @brief Get the location of the X-face center.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return Grid point location of the X-face center
     */
    Grid::Point XFace(const Index i, const Index j, const Index k) const;

    /**
     * @brief Get the location of the Y-face center.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return Grid point location of the Y-face center
     */
    Grid::Point YFace(const Index i, const Index j, const Index k) const;

    /**
     * @brief Get the location of the Z-face center.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return Grid point location of the Z-face center
     */
    Grid::Point ZFace(const Index i, const Index j, const Index k) const;

    /**
     * @brief Check if the given indices are valid for an X-face.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return True if valid, false otherwise
     */
    bool ValidXFace(const Index i, const Index j, const Index k) const noexcept;

    /**
     * @brief Check if the given indices are valid for a Y-face.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return True if valid, false otherwise
     */
    bool ValidYFace(const Index i, const Index j, const Index k) const noexcept;

    /**
     * @brief Check if the given indices are valid for a Z-face.
     * @param i Face I index
     * @param j Face J index
     * @param k Face K index
     * @return True if valid, false otherwise
     */
    bool ValidZFace(const Index i, const Index j, const Index k) const noexcept;

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//

   private:
    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    /**
     * @brief Geometry object describing the Cartesian domain.
     */
    const std::shared_ptr<CartesianGeometry> geometry_;

    /**
     * @brief Grid spacing in X, Y, Z directions.
     */
    double dx_, dy_, dz_;

    /**
     * @brief Number of cells in X, Y, Z directions.
     */
    const std::size_t n_cell_x_, n_cell_y_, n_cell_z_;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//
};

}  // namespace turbo
