#pragma once

#include <array>

#include "geometry.h"

namespace turbo {

// Abstract base class for discretized geometry
class Grid {
public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//
    using Index = std::size_t; 
    // Thinking ahead to AMReX IntVect actually uses int internally for this type of indexing. 
    // Because a index can be negative for ghost cells on the boundaries of the domain, etc.
    // For now this class is using std::size_t and assuming we do the checks/conversions when needed for potential negative indices for wrapping around the domain if doing periodic boundaries, ghost cells, etc.

    struct Point {
        double x, y, z;
        
        bool operator==(const Point&) const = default;

        Point operator+(const Point& other) const noexcept {
            return {x + other.x, y + other.y, z + other.z};
        };

    };

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//
    virtual ~Grid() = default;

    // Number of cells and nodes in the grid and in each direction
    virtual std::size_t NCell(void)  const noexcept = 0;
    virtual std::size_t NCellI(void) const noexcept = 0;
    virtual std::size_t NCellJ(void) const noexcept = 0;
    virtual std::size_t NCellK(void) const noexcept = 0;

    // Number of nodes in the grid and in each direction
    virtual std::size_t NNode(void)  const noexcept = 0;
    virtual std::size_t NNodeI(void) const noexcept = 0;
    virtual std::size_t NNodeJ(void) const noexcept = 0;
    virtual std::size_t NNodeK(void) const noexcept = 0;

    // Functions to get the location of a node, cell center, or face center in each direction
    virtual Point Node(const Index i, const Index j, const Index k) const = 0;
    virtual Point CellCenter(const Index i, const Index j, const Index k) const = 0;
    virtual Point IFace(const Index i, const Index j, const Index k) const = 0;
    virtual Point JFace(const Index i, const Index j, const Index k) const = 0;
    virtual Point KFace(const Index i, const Index j, const Index k) const = 0;

    protected:
    //-----------------------------------------------------------------------//
    // Protected Member Functions
    //-----------------------------------------------------------------------//
    // Functions to check if the given indices are valid for the grid for a given type of location
    virtual bool ValidNode(const Index i, const Index j, const Index k) const noexcept = 0;
    virtual bool ValidCell(const Index i, const Index j, const Index k) const noexcept = 0;
    virtual bool ValidIFace(const Index i, const Index j, const Index k) const noexcept = 0;
    virtual bool ValidJFace(const Index i, const Index j, const Index k) const noexcept = 0;
    virtual bool ValidKFace(const Index i, const Index j, const Index k) const noexcept = 0;

};

class CartesianGrid : public Grid {
public:
    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//
    CartesianGrid(const CartesianGeometry& geometry, 
                  const std::size_t n_cell_x, const std::size_t n_cell_y, const std::size_t n_cell_z)
        : geometry_(geometry),
          dx_(0.0), dy_(0.0), dz_(0.0),
          n_cell_x_(n_cell_x), n_cell_y_(n_cell_y), n_cell_z_(n_cell_z) {

        if (n_cell_x == 0 || n_cell_y == 0 || n_cell_z == 0) {
            throw std::invalid_argument("Number of cells in each direction must be greater than zero.");
        }
        // Make sure to do the division as double to avoid integer division... return value of LX() is promoted to double if it is not already. 
        dx_ = static_cast<double>(geometry_.LX()) / n_cell_x_;
        dy_ = static_cast<double>(geometry_.LY()) / n_cell_y_;
        dz_ = static_cast<double>(geometry_.LZ()) / n_cell_z_;
    }

    std::size_t NCell(void) const noexcept override { return NCellX() * NCellY() * NCellZ(); }
    std::size_t NCellI() const noexcept { return n_cell_x_; }
    std::size_t NCellJ() const noexcept { return n_cell_y_; }
    std::size_t NCellK() const noexcept { return n_cell_z_; }

    std::size_t NNode(void) const noexcept override { return NNodeX() * NNodeY() * NNodeZ(); }
    std::size_t NNodeI() const noexcept { return n_cell_x_ + 1; }
    std::size_t NNodeJ() const noexcept { return n_cell_y_ + 1; }
    std::size_t NNodeK() const noexcept { return n_cell_z_ + 1; }

    Point Node(const Index i, const Index j, const Index k) const override {

        if (!ValidNode(i,j,k)) {
            throw std::out_of_range("Node index out of bounds");
        }

        return Point({geometry_.XMin() + i * dx_,
                      geometry_.YMin() + j * dy_,
                      geometry_.ZMin() + k * dz_});
    };

    Point CellCenter(const Index i, const Index j, const Index k) const override {

        if (!ValidCell(i,j,k)) {
            throw std::out_of_range("Cell index out of bounds");
        }

        return Node(i,j,k) + Point{dx_*0.5, dy_*0.5, dz_*0.5};
    };

    Point IFace(const Index i, const Index j, const Index k) const override {
        return Node(i,j,k) + Point{0.0, dy_*0.5, dz_*0.5};
    };

    Point JFace(const Index i, const Index j, const Index k) const override {
        return Node(i,j,k) + Point{dx_*0.5, 0.0, dz_*0.5};
    };

    Point KFace(const Index i, const Index j, const Index k) const override {
        return Node(i,j,k) + Point{dx_*0.5, dy_*0.5, 0.0};
    };

    // Convenience functions for the common X,Y,Z notation
    std::size_t NNodeX(void) const noexcept { return NNodeI(); }
    std::size_t NNodeY(void) const noexcept { return NNodeJ(); }
    std::size_t NNodeZ(void) const noexcept { return NNodeK(); }
    std::size_t NCellX() const noexcept { return NCellI(); }
    std::size_t NCellY() const noexcept { return NCellJ(); }
    std::size_t NCellZ() const noexcept { return NCellK(); }
    Point XFace(const Index i, const Index j, const Index k) const { return IFace(i,j,k); };
    Point YFace(const Index i, const Index j, const Index k) const { return JFace(i,j,k); };
    Point ZFace(const Index i, const Index j, const Index k) const { return KFace(i,j,k); };

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    CartesianGeometry geometry_;
    double dx_, dy_, dz_;
    const std::size_t n_cell_x_, n_cell_y_, n_cell_z_;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

    // Check if the given indices are valid for the grid
    bool ValidNode(const Index i, const Index j, const Index k) const noexcept override {
        return (i >= 0 && i < NNodeX() &&
                j >= 0 && j < NNodeY() &&
                k >= 0 && k < NNodeZ());
    }

    bool ValidCell(const Index i, const Index j, const Index k) const noexcept override{
        return (i >= 0 && i < NCellX() &&
                j >= 0 && j < NCellY() &&
                k >= 0 && k < NCellZ());
    }

    bool ValidIFace(const Index i, const Index j, const Index k) const noexcept {
        return (i >= 0 && i < NNodeX() &&
                j >= 0 && j < NCellY() &&
                k >= 0 && k < NCellZ());
    };

    bool ValidJFace(const Index i, const Index j, const Index k) const noexcept{
        return (i >= 0 && i < NCellX() &&
                j >= 0 && j < NNodeY() &&
                k >= 0 && k < NCellZ());
    };

    bool ValidKFace(const Index i, const Index j, const Index k) const noexcept {
        return (i >= 0 && i < NCellX() &&
                j >= 0 && j < NCellY() &&
                k >= 0 && k < NNodeZ());
    };


    bool ValidXFace(const Index i, const Index j, const Index k) const noexcept { return ValidIFace(i,j,k); };
    bool ValidYFace(const Index i, const Index j, const Index k) const noexcept { return ValidJFace(i,j,k); };
    bool ValidZFace(const Index i, const Index j, const Index k) const noexcept { return ValidKFace(i,j,k); };

};

} // namespace turbo