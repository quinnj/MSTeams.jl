abstract type MSTeamsError <: Exception end

struct MSTeamsRequestError <: MSTeamsError
    message::String
end

struct MSTeamsAuthError <: MSTeamsError
    message::String
end

struct MSTeamsResponseError <: MSTeamsError
    message::String
    status::Int
end

struct MSTeamsConfigurationError <: MSTeamsError
    message::String
end

function Base.showerror(io::IO, err::MSTeamsRequestError)
    print(io, err.message)
    return
end

function Base.showerror(io::IO, err::MSTeamsAuthError)
    print(io, err.message)
    return
end

function Base.showerror(io::IO, err::MSTeamsResponseError)
    print(io, "$(err.message) (status=$(err.status))")
    return
end

function Base.showerror(io::IO, err::MSTeamsConfigurationError)
    print(io, err.message)
    return
end
