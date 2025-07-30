#pragma once

#include <cstddef>
#include <functional>
#include <type_traits>
#include <memory>
#include <vector>
#include <AMReX.H>
#include <AMReX_MultiFab.H>

class TripolarGrid {

public:
    // Types
    using value_t = double;

    struct Point {
        value_t x, y, z;
        bool operator==(const Point&) const = default;
        Point operator+(const Point& other) const noexcept;
    };

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

    template <typename Func>
    void InitializeScalarMultifabs(Func value_func) noexcept;

    // Multi-fabs to save data at each location in the grid.
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
    std::vector<std::shared_ptr<amrex::MultiFab>> all_multifabs;

    std::vector<std::shared_ptr<amrex::MultiFab>> scalar_multifabs;
    std::vector<std::shared_ptr<amrex::MultiFab>> vector_multifabs;

    std::vector<std::shared_ptr<amrex::MultiFab>> cell_multifabs;
    std::vector<std::shared_ptr<amrex::MultiFab>> x_face_multifabs;
    std::vector<std::shared_ptr<amrex::MultiFab>> y_face_multifabs;
    std::vector<std::shared_ptr<amrex::MultiFab>> z_face_multifabs;
    std::vector<std::shared_ptr<amrex::MultiFab>> node_multifabs;

private:
    const std::size_t n_cell_x_;
    const std::size_t n_cell_y_;
    const std::size_t n_cell_z_;

    const double x_min_=0.0;
    const double y_min_=0.0;
    const double z_min_=0.0;

    const double x_max_=1.0;
    const double y_max_=1.0;
    const double z_max_=1.0;

    const double Lx_=x_max_-x_min_;
    const double Ly_=y_max_-y_min_;
    const double Lz_=z_max_-z_min_;

    const double dx_=Lx_/n_cell_x_;
    const double dy_=Ly_/n_cell_y_;
    const double dz_=Lz_/n_cell_z_;
};

// Template implementation must remain in the header
template <typename Func>
void TripolarGrid::InitializeScalarMultifabs(Func value_func) noexcept {
    static_assert(
        std::is_invocable_r_v<double, Func, double, double, double>,
        "value_func must be callable as double(double, double, double)"
    );

    for (amrex::MFIter mfi(*cell_scalar); mfi.isValid(); ++mfi) {
        auto& arr = cell_scalar->array(mfi);
        amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
            const Point cell_center = CellCenter(amrex::IntVect(i,j,k));
            arr(i, j, k) = value_func(cell_center.x, cell_center.y, cell_center.z);
        });
    }

    // Repeat for x_face_scalar, y_face_scalar, z_face_scalar, node_scalar if needed
}
