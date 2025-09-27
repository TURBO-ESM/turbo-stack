#pragma once

#include <cstddef>
#include <string>

#include <hdf5.h>

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
    
    // Functions to get the location of a node, cell center, or face center
    virtual Point Node(const Index i, const Index j, const Index k) const = 0;
    virtual Point CellCenter(const Index i, const Index j, const Index k) const = 0;
    virtual Point IFace(const Index i, const Index j, const Index k) const = 0;
    virtual Point JFace(const Index i, const Index j, const Index k) const = 0;
    virtual Point KFace(const Index i, const Index j, const Index k) const = 0;

    virtual void WriteHDF5(const std::string& filename) const = 0;
    virtual void WriteHDF5(const hid_t file_id) const = 0;

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

} // namespace turbo
