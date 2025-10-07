#pragma once

#include <cstddef>
#include <memory>

#include <hdf5.h>

#include "grid.h"
#include "geometry.h"

namespace turbo {

class CartesianGrid : public Grid {
public:
    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//
    CartesianGrid(const std::shared_ptr<CartesianGeometry>& geometry, 
                  std::size_t n_cell_x, std::size_t n_cell_y, std::size_t n_cell_z);

    std::size_t NCell(void) const noexcept override;
    std::size_t NCellI() const noexcept override;
    std::size_t NCellJ() const noexcept override;
    std::size_t NCellK() const noexcept override;

    std::size_t NNode(void) const noexcept override;
    std::size_t NNodeI() const noexcept override;
    std::size_t NNodeJ() const noexcept override;
    std::size_t NNodeK() const noexcept override;

    Point Node(const Index i, const Index j, const Index k) const override;
    Point CellCenter(const Index i, const Index j, const Index k) const override;
    Point IFace(const Index i, const Index j, const Index k) const override;
    Point JFace(const Index i, const Index j, const Index k) const override;
    Point KFace(const Index i, const Index j, const Index k) const override;

    // Write the the grid data to a new HDF5 file with the given filename. Note this overwrites the file if it exists.
    void WriteHDF5(const std::string& filename) const;
    // Write the field data to an already open HDF5 file that you already have open.
    void WriteHDF5(const hid_t file_id) const override;

    // Convenience functions for the common X,Y,Z notation
    std::size_t NNodeX(void) const noexcept;
    std::size_t NNodeY(void) const noexcept;
    std::size_t NNodeZ(void) const noexcept;
    std::size_t NCellX() const noexcept;
    std::size_t NCellY() const noexcept;
    std::size_t NCellZ() const noexcept;
    Point XFace(const Index i, const Index j, const Index k) const;
    Point YFace(const Index i, const Index j, const Index k) const;
    Point ZFace(const Index i, const Index j, const Index k) const;

    // Check if the given indices are valid for the grid
    bool ValidNode(const Index i, const Index j, const Index k) const noexcept override;
    bool ValidCell(const Index i, const Index j, const Index k) const noexcept override;
    bool ValidIFace(const Index i, const Index j, const Index k) const noexcept override;
    bool ValidJFace(const Index i, const Index j, const Index k) const noexcept override;
    bool ValidKFace(const Index i, const Index j, const Index k) const noexcept override;

    // Convenience functions for the common X,Y,Z notation
    bool ValidXFace(const Index i, const Index j, const Index k) const noexcept;
    bool ValidYFace(const Index i, const Index j, const Index k) const noexcept;
    bool ValidZFace(const Index i, const Index j, const Index k) const noexcept;

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//


private:
    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    const std::shared_ptr<CartesianGeometry> geometry_;
    double dx_, dy_, dz_;
    const std::size_t n_cell_x_, n_cell_y_, n_cell_z_;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

};

} // namespace turbo
