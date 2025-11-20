#pragma once

#include <AMReX.H>
#include <AMReX_MultiFab.H>
#include <hdf5.h>

#include <cstddef>
#include <functional>
#include <memory>
#include <string>
#include <type_traits>
#include <unordered_set>

class TripolarGrid
{
   public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//
    using ValueType = amrex::Real;

    struct Point
    {
        ValueType x, y, z;
        bool operator==(const Point&) const = default;
        Point operator+(const Point& other) const noexcept;
    };

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    TripolarGrid(std::size_t n_cell_x, std::size_t n_cell_y, std::size_t n_cell_z);

    // Grid dimensions
    std::size_t NCell() const noexcept;
    std::size_t NCellX() const noexcept;
    std::size_t NCellY() const noexcept;
    std::size_t NCellZ() const noexcept;

    std::size_t NNode() const noexcept;
    std::size_t NNodeX() const noexcept;
    std::size_t NNodeY() const noexcept;
    std::size_t NNodeZ() const noexcept;

    // Geometry
    Point Node(amrex::IntVect node_index) const noexcept;
    Point CellCenter(amrex::IntVect cell_index) const noexcept;
    Point XFace(amrex::IntVect x_face_index) const noexcept;
    Point YFace(amrex::IntVect y_face_index) const noexcept;
    Point ZFace(amrex::IntVect z_face_index) const noexcept;

    // Function to get the location of a point in the grid for a given MultiFab and index i,j,k
    Point GetLocation(const std::shared_ptr<amrex::MultiFab>& mf, int i, int j, int k) const;

    // Convenience functions to initialize all the scalar and vector MultiFabs given a function
    template <typename Func>
    void InitializeScalarMultiFabs(Func initialization_function) noexcept;

    template <typename Func>
    void InitializeVectorMultiFabs(Func initialization_function) noexcept;

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
    const std::size_t n_cell_x_;
    const std::size_t n_cell_y_;
    const std::size_t n_cell_z_;

    const double x_min_ = 0.0;
    const double y_min_ = 0.0;
    const double z_min_ = 0.0;

    const double x_max_ = 1.0;
    const double y_max_ = 1.0;
    const double z_max_ = 1.0;

    const double Lx_    = x_max_ - x_min_;
    const double Ly_    = y_max_ - y_min_;
    const double Lz_    = z_max_ - z_min_;

    const double dx_    = Lx_ / n_cell_x_;
    const double dy_    = Ly_ / n_cell_y_;
    const double dz_    = Lz_ / n_cell_z_;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

    // Utility to copy a MultiFab to a single rank
    // Returns a pointer to a new MultiFab that contains all the data from the original MultiFab but now on a single box
    // and rank.
    std::shared_ptr<amrex::MultiFab> CopyMultiFabToSingleRank(const std::shared_ptr<amrex::MultiFab>& src_mf,
                                                              int dest_rank = 0) const;

    void WriteMultiFabsToHDF5(const hid_t file_id) const;

    void WriteGeometryToHDF5(const hid_t file_id) const;

    // void WriteXDMF(const std::string& h5_filename,
    //                const std::string& xdmf_filename) const;
};

// Template implementation must remain in the header
template <typename Func>
void TripolarGrid::InitializeScalarMultiFabs(Func initializer_function) noexcept
{
    static_assert(std::is_invocable_r_v<double, Func, double, double, double>,
                  "initializer_function must be callable as double(double, double, double). The arguments are the x, "
                  "y, and z coordinates of the point and the return value is the function evaluated at that point.");

    for (const std::shared_ptr<amrex::MultiFab>& mf : scalar_multifabs)
    {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi)
        {
            const amrex::Array4<amrex::Real>& array = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(),
                               [=, this] AMREX_GPU_DEVICE(int i, int j, int k)
                               {
                                   const Point location = GetLocation(mf, i, j, k);
                                   array(i, j, k)       = initializer_function(location.x, location.y, location.z);
                               });
        }
    }
}

template <typename Func>
void TripolarGrid::InitializeVectorMultiFabs(Func initializer_function) noexcept
{
    static_assert(std::is_invocable_r_v<std::array<double, 3>, Func, double, double, double>,
                  "initializer_function must be callable as std::array<double, 3>(double, double, double). The "
                  "arguments are the x, y, and z coordinates of the point and the return value is an array of 3 "
                  "doubles representing the vector function evaluated at that point.");

    for (const std::shared_ptr<amrex::MultiFab>& mf : vector_multifabs)
    {
        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi)
        {
            const amrex::Array4<amrex::Real>& array = mf->array(mfi);
            amrex::ParallelFor(mfi.validbox(),
                               [=, this] AMREX_GPU_DEVICE(int i, int j, int k)
                               {
                                   const Point location = GetLocation(mf, i, j, k);
                                   std::array<double, 3> initial_vector =
                                       initializer_function(location.x, location.y, location.z);
                                   array(i, j, k, 0) = initial_vector[0];
                                   array(i, j, k, 1) = initial_vector[1];
                                   array(i, j, k, 2) = initial_vector[2];
                               });
        }
    }
}
